defmodule Maty.Typechecker.TC do
  require Logger

  alias Maty.ST.SBottom
  alias Maty.{Check, Types}
  alias Maty.Typechecker.{Error, Helpers, TC, Ctx}

  import Maty.Check
  import Maty.Utils, only: [deftc: 2]
  import Maty.Types, only: [is_label: 1]

  @typedoc """
  Represents Elixir AST nodes that can be typechecked.
  """
  @type ast :: Macro.t()

  @type result :: Check.result(Types.T.t())

  # -- AST shapes
  # The typechecker sees expanded AST some relatively short forms expand to very large nodes
  # so here we just name the large nodes so the clause heads stay readable
  # since a macro in a pattern expands to that pattern

  # `not x`, `a + b`, `a <= b`, ...: `:erlang.op(args)`
  defmacrop erlang(op, meta, args) do
    quote do
      {{:., unquote(meta), [:erlang, unquote(op)]}, _, unquote(args)}
    end
  end

  # `send`, `suspend`, `done`, `register`: `Maty.Runtime.fun(args)`
  defmacrop maty_runtime(fun, meta, args) do
    quote do
      {{:., _, [Maty.Runtime, unquote(fun)]}, unquote(meta), unquote(args)}
    end
  end

  # the comparison operators whose Erlang name differs from the source one (`a <= b` expands to `:erlang.=<`),
  # mapped back so `op_type_rel` and the errors see what the user wrote
  @source_ops %{"=<": :<=, "/=": :!=}

  # `||`, `&&`, `!`, `if`: `x when x === false or x === nil`
  defmacrop falsy_guard do
    quote do
      {:when, _,
       [
         {:x, _, Kernel},
         erlang(:orelse, _, [
           erlang(:"=:=", _, [{:x, _, Kernel}, false]),
           erlang(:"=:=", _, [{:x, _, Kernel}, nil])
         ])
       ]}
    end
  end

  # `a and b`: `case a do false -> false; true -> b end`
  defmacrop boolean_op(:and, meta, lhs, rhs) do
    quote do
      {:case, unquote(meta),
       [unquote(lhs), [do: [{:->, _, [[false], false]}, {:->, _, [[true], unquote(rhs)]} | _]]]}
    end
  end

  # `a or b`: `case a do false -> b; true -> true end`
  defmacrop boolean_op(:or, meta, lhs, rhs) do
    quote do
      {:case, unquote(meta),
       [unquote(lhs), [do: [{:->, _, [[false], unquote(rhs)]}, {:->, _, [[true], true]} | _]]]}
    end
  end

  # `a && b`: `case a do x when <falsy x> -> x; _ -> b end`
  defmacrop truthy_op(:&&, meta) do
    quote do
      {:case, unquote(meta),
       [_, [do: [{:->, _, [[falsy_guard()], {:x, _, Kernel}]}, {:->, _, [[{:_, _, _}], _]}]]]}
    end
  end

  # `a || b`: `case a do x when <falsy x> -> b; x -> x end`
  defmacrop truthy_op(:||, meta) do
    quote do
      {:case, unquote(meta),
       [_, [do: [{:->, _, [[falsy_guard()], _]}, {:->, _, [[{:x, _, Kernel}], {:x, _, Kernel}]}]]]}
    end
  end

  @doc """
  Typechecks an expression AST node within a given variable environment and
  session state pre-condition.

  Corresponds to the formal judgement: Ψ; Δ; Γ ∣ Q₁ ⊳ e : T ⊲ Q₂

  Returns:
    - `{:ok, elixir_type, next_session_state, var_env}` on success
    - `{:error, error, var_env}` on failure
  """
  @spec synth(Ctx.t(), Check.var_env(), Maty.ST.t(), ast()) :: result()

  # -- TV-Const
  deftc synth(_ctx, env, st, nil), do: {:ok, nil, st, env}
  deftc synth(_ctx, env, st, value) when is_boolean(value), do: {:ok, :boolean, st, env}
  deftc synth(_ctx, env, st, value) when is_binary(value), do: {:ok, :binary, st, env}
  deftc synth(_ctx, env, st, value) when is_number(value), do: {:ok, :number, st, env}

  # -- TV-Nil-Syn
  deftc synth(ctx, env, _st, []) do
    error = Error.TypeInference.cannot_infer_type(ctx.module, ctx.meta, :empty_list)
    {:error, error, env}
  end

  # -- TV-Cons-Syn
  # List Construction [v1, v2, ...] or [v | vs] both match
  deftc synth(ctx, env, st, [_ | _] = xs) do
    {[v | vs], tail} = normalise_list_shapes(xs)

    tcm env: env, st: st do
      ty <- syn(ctx, v) |> with_frame({:list_element, 1})

      chain(vs |> Enum.with_index(2), fn {v, i} ->
        chk(ctx, v, ty) |> with_frame({:list_element, i})
      end)

      chk(ctx, tail, {:list, ty}) |> with_frame(:list_tail)

      ok({:list, ty})
    end
  end

  # -- TV-Tuple-Syn
  # Empty Tuple Construction
  deftc synth(_ctx, env, st, {:{}, _, []}) do
    {:ok, {:tuple, []}, st, env}
  end

  # -- TV-Tuple-Syn
  # 2-Tuple Value Construction
  deftc synth(ctx, env, st, {lhs_ast, rhs_ast}) do
    tcm env: env, st: st do
      lhs_type <- syn(ctx, lhs_ast) |> with_frame({:tuple_element, 1})
      rhs_type <- syn(ctx, rhs_ast) |> with_frame({:tuple_element, 2})
      ok({:tuple, [lhs_type, rhs_type]})
    end
  end

  # -- TV-Tuple-Syn
  # n-Tuple Construction {v1, v2, ...}
  deftc synth(ctx, var_env, st_pre, {:{}, _, items}) when is_list(items) do
    tcm env: var_env, st: st_pre do
      types <-
        chain(items |> Enum.with_index(1), fn {item, i} ->
          syn(ctx, item) |> with_frame({:tuple_element, i})
        end)

      ok({:tuple, types})
    end
  end

  # Map Record Update %{m | k1: v1, ...}
  # every key must already be in the record and keep its field's type, so the result has the record's type
  # (at runtime `|` raises a KeyError for a missing key, so an update can never add a key)
  deftc synth(ctx, env, st, {:%{}, meta, [{:|, _, [map_ast, updates]}]})
        when is_list(updates) do
    tcm env: env, st: st do
      map_type <- syn(ctx, map_ast)

      expect {:map_record, fields} = map_type,
        else: Error.TypeMismatch.map_update_not_record(ctx.module, meta, got: map_type)

      chain(updates, fn {k, v_ast} ->
        tcm do
          # keys must be literal atoms, a record's fields are known statically
          expect is_atom(k),
            else: Error.PatternMatching.complex_map_key(ctx.module, meta, k)

          expect is_label(k),
            else: Error.TypeMismatch.invalid_record_label(ctx.module, meta, k)

          expect {:ok, field_type} = Map.fetch(fields, k),
            else: Error.TypeMismatch.map_update_key_not_found(ctx.module, meta, k, map_type)

          chk(ctx, v_ast, field_type) |> with_frame({:record_field, k})

          ok()
        end
      end)

      ok(map_type)
    end
  end

  # -- TV-Dict-Syn (n = 0)
  # Empty Dict %{}
  deftc synth(ctx, env, _st, {:%{}, meta, []}) do
    error = Error.TypeInference.cannot_infer_type(ctx.module, meta, :empty_map)
    {:error, error, env}
  end

  # -- TV-Dict-Syn / TV-Record-Syn
  # Map Construction %{k1 => v1, ...}
  # an atom-keyed dict has the same shape as a record, so the keys decide:
  # a record when every key is a label, a dict otherwise (whatever order the keys come in)
  # a label is a literal atom other than `true`, `false` and `nil`, which TV-Const types as Bool and Nil, not Atom
  deftc synth(ctx, env, st, {:%{}, meta, pairs}) do
    if Enum.all?(pairs, fn {k, _} -> is_label(k) end) do
      synth_record(ctx, env, st, meta, pairs)
    else
      synth_dict(ctx, env, st, meta, pairs)
    end
  end

  # Map Record Field Access m.k
  # expanded AST: {{:., _, [map_ast, key]}, [no_parens: true, ...], []}
  # a zero-arity remote call `Mod.fun()` has the same shape, but its left-hand side is always a module atom
  deftc synth(ctx, env, st, {{:., meta, [map_ast, key]}, _call_meta, []})
        when not is_atom(map_ast) and is_atom(key) do
    tcm env: env, st: st do
      map_type <- syn(ctx, map_ast)

      expect {:map_record, fields} = map_type,
        else: Error.TypeMismatch.field_access_not_record(ctx.module, meta, got: map_type)

      expect {:ok, val_type} = Map.fetch(fields, key),
        else: Error.TypeMismatch.field_access_key_not_found(ctx.module, meta, key, map_type)

      ok(val_type)
    end
  end

  # -- T-Not
  deftc synth(ctx, env, st, erlang(:not, meta, [operand_ast])) do
    tcm env: env, st: st do
      res_type <- syn(ctx, operand_ast)

      expect res_type == :boolean,
        else:
          Error.TypeMismatch.logical_operator_requires_boolean(
            ctx.module,
            meta,
            :not,
            res_type
          )

      ok(:boolean)
    end
  end

  # Unary minus `-x`
  deftc synth(ctx, env, st, erlang(:-, meta, [operand_ast])) do
    tcm env: env, st: st do
      operand_type <- syn(ctx, operand_ast)

      expect operand_type == :number,
        else:
          Error.TypeMismatch.arithmetic_operator_requires_number(
            ctx.module,
            meta,
            :-,
            operand_type
          )

      ok(:number)
    end
  end

  # -- T-Op
  deftc synth(ctx, env, st, erlang(erlang_op, meta, [lhs_ast, rhs_ast]))
        when erlang_op in [:+, :-, :*, :/, :<, :>, :"=<", :>=, :==, :"/="] do
    op = Map.get(@source_ops, erlang_op, erlang_op)

    tcm env: env, st: st do
      lhs_type <- syn(ctx, lhs_ast)
      rhs_type <- syn(ctx, rhs_ast)

      expect {:ok, res_type} = Helpers.op_type_rel(op, lhs_type, rhs_type),
        else:
          Error.TypeMismatch.binary_operator_type_mismatch(
            ctx.module,
            meta,
            op,
            lhs_type,
            rhs_type
          )

      ok(res_type)
    end
  end

  # Strings: Concatenation and Interpolation
  # after expansion both `"a" <> b <> "c"` and `"a=#{n}"` are a single `<<>>` with one `segment :: binary` per part
  # Other bitstring syntax (sizes, integer segments, ...) is not supported
  deftc synth(ctx, env, st, {:<<>>, meta, segments}) when is_list(segments) do
    tcm env: env, st: st do
      _ <- chain(segments, &tc_string_segment(ctx, meta, &1))
      ok(:binary)
    end
  end

  # Handles Boolean Ops: and, or
  # matched in the `case` they expand to (see `boolean_op/4`)
  deftc synth(ctx, env, st, boolean_op(:and, meta, lhs_ast, rhs_ast)) do
    tc_boolean_op(ctx, env, st, :and, meta, lhs_ast, rhs_ast)
  end

  deftc synth(ctx, env, st, boolean_op(:or, meta, lhs_ast, rhs_ast)) do
    tc_boolean_op(ctx, env, st, :or, meta, lhs_ast, rhs_ast)
  end

  # rejected cause they're annoying to type
  deftc synth(ctx, env, _st, truthy_op(:&&, meta)) do
    {:error, Error.FrameworkUsage.unsupported_truthy_operator(ctx.module, meta, :&&), env}
  end

  deftc synth(ctx, env, _st, truthy_op(:||, meta)) do
    {:error, Error.FrameworkUsage.unsupported_truthy_operator(ctx.module, meta, :||), env}
  end

  # Raw Communication Checks
  # todo: can probably move these much further down

  # Disallow raw 'receive'
  deftc synth(ctx, env, _st, {:receive, meta, _}) do
    {:error, Error.FrameworkUsage.no_native_receive(ctx.module, meta), env}
  end

  # Disallow raw 'send' (Kernel.send/2 or :erlang.send/2)
  deftc synth(ctx, env, _st, erlang(:send, meta, args))
        when length(args) in [2, 3] do
    {:error, Error.FrameworkUsage.no_native_send(ctx.module, meta), env}
  end

  # Anonymous Functions and Captures
  # not supported: would require either type annotations (which do not exist in the language in any capacity)
  # or type inference (which was not really the point of this project)
  # Reject them explicitly so they do not fall through to T-App

  # Anonymous function: fn args -> ... end
  deftc synth(ctx, env, _st, {:fn, meta, _clauses}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # Function capture: &fun/arity
  deftc synth(ctx, env, st, {:&, meta, [{:/, _, [{name, _, context}, arity]}]})
        when is_atom(name) and is_atom(context) and is_integer(arity) do
    tcm env: env, st: st do
      # a handler is in Σ under its name, a function under `{module, name, arity}`
      case {Map.get(ctx.signatures, name), arity} do
        # TV-MsgHandler
        {{:handler, :message, _} = handler_type, 3} ->
          ok(handler_type)

        {{:handler, :message, _}, _} ->
          fail(Error.FrameworkUsage.handler_ref_wrong_arity(ctx.module, meta, name, arity, 3))

        # TV-InitHandler
        {{:handler, :init, _, _} = handler_type, 2} ->
          ok(handler_type)

        {{:handler, :init, _, _}, _} ->
          fail(Error.FrameworkUsage.handler_ref_wrong_arity(ctx.module, meta, name, arity, 2))

        _ ->
          tcm do
            f = {ctx.module, name, arity}

            expect {:ok, ty} = Map.fetch(ctx.signatures, f),
              else: Error.FunctionCall.function_not_exist(ctx.module, meta, f)

            ok(ty)
          end
      end
    end
  end

  # Remote function capture: &Mod.fun/arity
  # handlers are always local, so a remote capture is never one
  deftc synth(
          ctx,
          env,
          st,
          {:&, meta, [{:/, _, [{{:., _, [mod, fun]}, _, []}, arity]}]}
        )
        when is_atom(mod) and is_atom(fun) and is_integer(arity) do
    tcm env: env, st: st do
      f = {mod, fun, arity}

      expect {:ok, func_type} = Map.fetch(ctx.signatures, f),
        else: Error.FunctionCall.function_not_exist(ctx.module, meta, f)

      ok(func_type)
    end
  end

  # Anonymus Function capture: &(&1 + 1)
  deftc synth(ctx, env, _st, {:&, meta, [_capture]}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # todo: handle remote function call

  # Block Scope
  deftc synth(ctx, var_env, st_pre, {:__block__, _, body_asts}) when is_list(body_asts) do
    # todo: reconsider what to do here..
    tc_expr_list(ctx, var_env, st_pre, body_asts)
  end

  # -- T-Let
  deftc synth(ctx, env, st, {:=, _meta, [pat_ast, expr_ast]}) do
    tcm env: env, st: st do
      expr_type <- syn(ctx, expr_ast)
      _ <- match_pattern(ctx, pat_ast, expr_type)
      ok(expr_type)
    end
  end

  # -- T-Case
  # todo: revisit this
  deftc synth(ctx, env, st, {:case, meta, [scrutinee_ast, [do: clauses_list]]}) do
    tcm env: env, st: st do
      scrutinee_type <- syn(ctx, scrutinee_ast)

      branch_results <-
        fan_out(Enum.with_index(clauses_list, 1), fn
          {{:->, branch_meta, [[pat_ast], expr_ast]}, index} ->
            tcm do
              # a literal pattern has no meta of its own, so its errors are reported at the branch
              _ <- match_pattern(%{ctx | meta: branch_meta}, pat_ast, scrutinee_type)
              syn(ctx, expr_ast)
            end
            |> with_frame({:case_branch, index, Keyword.take(branch_meta, [:line, :column])})
        end)

      case Helpers.join_branch_results(branch_results) do
        {:error, failed} ->
          fail(Error.TypeMismatch.case_branches_incompatible(ctx.module, meta, failed))

        {:ok, {branch_type, joined_st}} ->
          ok(branch_type, st: joined_st)
      end
    end
  end

  # -- T-Send
  deftc synth(
          ctx,
          env,
          st_pre,
          maty_runtime(:send_session_message, meta, [_, recipient_ast, message_ast])
        ) do
    tcm env: env, st: st_pre do
      # the message must be a literal 2-tuple
      expect {literal_label, payload_expr_ast} = message_ast,
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      # the label of a message, must be an atom
      expect is_atom(literal_label),
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      actual_payload_type <- syn(ctx, payload_expr_ast)

      # roles must be literal atoms
      expect is_atom(recipient_ast),
        else: Error.FrameworkUsage.role_not_literal(ctx.module, meta, recipient_ast)

      expect_st %ST.SOut{to: expected_role, branches: branches} = q,
        else: fn st ->
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: {:send, [recipient_ast, message_ast]}],
            st
          )
        end

      expect recipient_ast == expected_role,
        else:
          Error.ProtocolViolation.incorrect_target_participant(
            ctx.module,
            meta,
            q,
            got: recipient_ast,
            expected: expected_role
          )

      # choosing a branch of the session type is static
      case Helpers.try_get_matching_branch(branches, literal_label, actual_payload_type) do
        {:ok, branch} ->
          ok(:atom, st: branch.continue_as)

        {:error, :label_mismatch} ->
          fail(
            Error.ProtocolViolation.incorrect_message_label(
              ctx.module,
              meta,
              q,
              got: literal_label,
              expected: Enum.map(branches, & &1.label)
            )
          )

        {:error, :payload_mismatch, branch} ->
          fail(
            Error.ProtocolViolation.incorrect_payload_type(
              ctx.module,
              meta,
              q,
              got: actual_payload_type,
              expected: branch.payload
            )
          )
      end
    end
  end

  # Demo only (I really do not like these)
  # todo: tidy up

  deftc synth(ctx, var_env, st_pre, {{:., _, [IO, _]}, _, _} = ast) do
    TC.IO.synth(ctx, var_env, st_pre, ast)
  end

  deftc synth(ctx, var_env, st_pre, {{:., _, [:timer, _]}, _, _} = ast) do
    TC.Timer.synth(ctx, var_env, st_pre, ast)
  end

  # -- T-Suspend
  deftc synth(
          ctx,
          env,
          st,
          maty_runtime(:suspend, meta, [handler_ast, state_ast])
        ) do
    tcm env: env, st: st do
      handler_type <- syn(ctx, handler_ast)

      expect {:handler, :message, handler_st} = handler_type,
        else: Error.TypeMismatch.handler_expected(ctx.module, meta, :message, handler_type)

      state_type <- syn(ctx, state_ast)

      expect state_type == Types.T.maty_actor_state(),
        else:
          Error.TypeMismatch.invalid_maty_state_type(
            ctx.module,
            meta,
            Error.TypeMismatch.invalid_maty_state_cause(state_type)
          )

      expect_st %ST.SName{handler: expected_handler} = q,
        else: fn st ->
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: {:suspend, [handler_ast, state_ast]}],
            st
          )
        end

      expect {:ok, %{st: expected_st}} = Map.fetch(ctx.delta_M, expected_handler),
        else:
          Error.ProtocolViolation.undefined_continuation_handler(
            ctx.module,
            meta,
            q,
            expected_handler
          )

      expect handler_st == expected_st,
        else:
          Error.ProtocolViolation.handler_session_type_mismatch(
            ctx.module,
            meta,
            q,
            expected_handler,
            got: handler_st,
            expected: expected_st
          )

      ok(:no_return, st: %SBottom{reason: :suspend})
    end
  end

  # -- T-Done
  deftc synth(
          ctx,
          env,
          st,
          maty_runtime(:done, meta, [state_ast])
        ) do
    tcm env: env, st: st do
      state_type <- syn(ctx, state_ast)

      expect state_type == Types.T.maty_actor_state(),
        else:
          Error.TypeMismatch.invalid_maty_state_type(
            ctx.module,
            meta,
            Error.TypeMismatch.invalid_maty_state_cause(state_type)
          )

      expect_st %ST.SEnd{},
        else: fn st ->
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: {:done, [state_ast]}],
            st
          )
        end

      ok(:no_return, st: %SBottom{reason: :done})
    end
  end

  # -- T-Register
  deftc synth(
          ctx,
          env,
          st,
          maty_runtime(:register, meta, [
            ap_pid_ast,
            role_ast,
            handler_ast,
            args_ast
          ])
        ) do
    tcm env: env, st: st do
      pid_type <- syn(ctx, ap_pid_ast)

      expect pid_type == :pid,
        else:
          Error.TypeMismatch.register_arg_type_mismatch(
            ctx.module,
            meta,
            :access_point,
            expected: :pid,
            got: pid_type
          )

      # the role must be known statically, as it is what pairs the init handler with a projection of the protocol
      expect is_atom(role_ast),
        else: Error.FrameworkUsage.role_not_literal(ctx.module, meta, role_ast)

      expect role_ast in ctx.roles,
        else: Error.FrameworkUsage.undeclared_role(ctx.module, meta, role_ast, ctx.roles)

      handler_type <- syn(ctx, handler_ast)

      expect {:handler, :init, arg_type, _st} = handler_type,
        else: Error.TypeMismatch.handler_expected(ctx.module, meta, :init, handler_type)

      args_type <- syn(ctx, args_ast)

      expect args_type == arg_type,
        else:
          Error.TypeMismatch.register_arg_type_mismatch(
            ctx.module,
            meta,
            :init_handler_args,
            expected: arg_type,
            got: args_type
          )

      ok(:atom)
    end
  end

  # -- T-App
  # todo: how could I handle remote calls?
  deftc synth(ctx, env, st, {func_name, meta, arg_asts})
        when is_atom(func_name) and is_list(arg_asts) and meta != [] and
               func_name not in [:=, :%, :{}, :|, :<<>>] do
    func_id = {func_name, length(arg_asts)}

    tcm env: env, st: st do
      expect not match?({:handler, :message, _}, ctx.signatures[func_name]),
        else: Error.FunctionCall.handler_called_directly(ctx.module, meta, func_id, :message)

      expect not match?({:handler, :init, _, _}, ctx.signatures[func_name]),
        else: Error.FunctionCall.handler_called_directly(ctx.module, meta, func_id, :init)

      # a function has one signature, under `{module, name, arity}` in Σ
      expect {:ok, {:function, param_types, return_type}} =
               Map.fetch(ctx.signatures, {ctx.module, func_name, length(arg_asts)}),
             else: Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)

      arg_types <-
        arg_asts
        |> chain(&syn(ctx, &1))
        |> with_frame({:call, func_id, Keyword.take(meta, [:line, :column])})

      expect arg_types == param_types,
        else:
          Error.FunctionCall.no_matching_function_clause(
            ctx.module,
            meta,
            func_id,
            arg_types
          )

      ok(return_type)
    end
  end

  # -- TV-Var
  # x : A ∈ Γ
  # a variable's context is `nil`
  # variables introduced by some macro would have an atom context, currently Γ is keyed by name only,
  # so looking those up could pick up the user's variable of the same name so they are left to the catch-all below
  deftc synth(ctx, env, st, {x, meta, nil}) when is_atom(x) do
    case Map.fetch(env, x) do
      {:ok, type} ->
        {:ok, type, st, env}

      :error ->
        {:error, Error.NameResolution.variable_not_exist(ctx.module, meta, x), env}
    end
  end

  # -- TV-Const
  # Atom literals
  deftc synth(_ctx, env, st, value) when is_atom(value) and not is_nil(value) do
    {:ok, :atom, st, env}
  end

  # Catch-all: anything no rule above covers is reported
  deftc synth(ctx, env, _st, ast) do
    meta = Helpers.extract_meta_from_ast(ast)
    meta = if Keyword.has_key?(meta, :line), do: meta, else: ctx.meta
    {:error, Error.FrameworkUsage.unsupported_expression(ctx.module, meta, ast), env}
  end

  # -- start of other little bits --------------------------------------------------------------------------------

  # types that String.Chars implements
  @interpolatable_types [:atom, :binary, :boolean, :date, :number, nil]

  # an interpolated value: `String.Chars.to_string(x) :: binary`
  defp tc_string_segment(
         ctx,
         meta,
         {:"::", seg_meta, [{{:., _, [String.Chars, :to_string]}, _, [val_ast]}, {:binary, _, _}]}
       ) do
    tcm do
      val_type <- syn(ctx, val_ast)

      expect val_type in @interpolatable_types,
        else:
          Error.TypeMismatch.string_segment_type_mismatch(
            ctx.module,
            segment_meta(seg_meta, meta),
            :interpolation,
            expected: @interpolatable_types,
            got: val_type
          )

      ok(val_type)
    end
  end

  # a literal or concatenated operand: `x :: binary`
  defp tc_string_segment(ctx, meta, {:"::", seg_meta, [val_ast, {:binary, _, _}]}) do
    tcm do
      val_type <- syn(ctx, val_ast)

      expect val_type == :binary,
        else:
          Error.TypeMismatch.string_segment_type_mismatch(
            ctx.module,
            segment_meta(seg_meta, meta),
            :concatenation,
            expected: [:binary],
            got: val_type
          )

      ok(:binary)
    end
  end

  defp tc_string_segment(ctx, meta, _segment) do
    fail(Error.FrameworkUsage.unsupported_bitstring(ctx.module, meta))
  end

  # segments of literal parts carry no column of their own, fall back to the whole string
  defp segment_meta(seg_meta, meta) do
    if Keyword.has_key?(seg_meta, :line), do: seg_meta, else: meta
  end

  defp tc_boolean_op(ctx, env, st, op, meta, lhs_ast, rhs_ast) do
    tcm env: env, st: st do
      lhs_type <- syn(ctx, lhs_ast)
      rhs_type <- syn(ctx, rhs_ast)

      expect {:ok, res_type} = Helpers.op_type_rel(op, lhs_type, rhs_type),
        else:
          Error.TypeMismatch.logical_operator_type_mismatch(
            ctx.module,
            meta,
            op,
            lhs_type,
            rhs_type
          )

      ok(res_type)
    end
  end

  # -- TV-Dict-Syn
  # Dictionary Construction %{k1 => v1, ...}
  # only reached when some key is not a label (non-empty, the empty map has its own clause)
  defp synth_dict(ctx, env, st, meta, [{k, v_ast} | rest]) do
    tcm env: env, st: st do
      k_ty <- syn(ctx, k) |> with_frame({:dict_key, 1})

      expect Types.is_base_type?(k_ty),
        else: Error.TypeMismatch.dict_key_not_base_type(ctx.module, meta, got: k_ty)

      v_ty <- syn(ctx, v_ast) |> with_frame({:dict_value, 1})

      chain(rest |> Enum.with_index(2), fn {{k_i, v_ast_i}, i} ->
        tcm do
          chk(ctx, k_i, k_ty) |> with_frame({:dict_key, i})
          chk(ctx, v_ast_i, v_ty) |> with_frame({:dict_value, i})
          ok()
        end
      end)

      ok({:map_dict, {k_ty, v_ty}})
    end
  end

  # -- TV-Record-Syn
  # Record Construction %{k1: v1, ...}
  # atom-keyed dict is also inferred as a record
  # only reached when every key is a label
  defp synth_record(ctx, env, st, meta, pairs) do
    tcm env: env, st: st do
      labels = Enum.map(pairs, fn {k, _} -> k end)
      duplicates = labels -- Enum.uniq(labels)

      expect duplicates == [],
        else: Error.TypeMismatch.record_duplicate_label(ctx.module, meta, hd(duplicates))

      fields <-
        chain(pairs, fn {k, v_ast} ->
          tcm do
            v_ty <- syn(ctx, v_ast) |> with_frame({:record_field, k})
            ok({k, v_ty})
          end
        end)

      ok({:map_record, Map.new(fields)})
    end
  end

  defp normalise_list_shapes(xs) do
    case Enum.split(xs, -1) do
      {init, [{:|, _, [x, tail]}]} -> {init ++ [x], tail}
      _ -> {xs, []}
    end
  end

  # Processes a list of expressions sequentially using synth.
  # Returns the result of the *last* expression in the list.
  # the only reason this isn't inlined is because it's used in a bunch of places in the wf module
  @spec tc_expr_list(Ctx.t(), Check.var_env(), Maty.ST.t(), [ast()]) :: result()
  def tc_expr_list(ctx, var_env, st_pre, ast_list) do
    tcm env: var_env, st: st_pre do
      types <- chain(ast_list, &syn(ctx, &1))
      ok(List.last(types))
    end
  end

  # -- end of other little bits --------------------------------------------------------------------------------

  @spec check(Ctx.t(), Check.var_env(), Maty.ST.t(), ast(), Types.T.t()) :: result()

  # -- TV-Tuple-Chk
  # ? maybe this one is not necessary
  deftc check(_ctx, env, st, {:{}, _, []}, {:tuple, []} = t), do: {:ok, t, st, env}

  # 2-Tuple Construction
  deftc check(ctx, env, st, {lhs_ast, rhs_ast}, {:tuple, types} = t) do
    tcm env: env, st: st do
      expect [lhs_t, rhs_t] = types,
        # a 2-tuple literal has no meta of its own
        else:
          Error.TypeMismatch.tuple_arity_mismatch(ctx.module, ctx.meta,
            expected: length(types),
            got: 2
          )

      chk(ctx, lhs_ast, lhs_t) |> with_frame({:tuple_element, 1})
      chk(ctx, rhs_ast, rhs_t) |> with_frame({:tuple_element, 2})
      ok(t)
    end
  end

  # n-Tuple Construction {v1, v2, ...}
  deftc check(ctx, var_env, st_pre, {:{}, meta, vs}, {:tuple, types} = t)
        when is_list(vs) do
    tcm env: var_env, st: st_pre do
      type_arity = length(types)
      tuple_arity = length(vs)

      expect type_arity == tuple_arity,
        else:
          Error.TypeMismatch.tuple_arity_mismatch(ctx.module, meta,
            expected: type_arity,
            got: tuple_arity
          )

      chain(Enum.zip(vs, types) |> Enum.with_index(1), fn {{v, ty}, i} ->
        chk(ctx, v, ty) |> with_frame({:tuple_element, i})
      end)

      ok(t)
    end
  end

  # -- TV-Nil
  deftc check(_ctx, env, st, [], {:list, _ty} = t), do: {:ok, t, st, env}

  # -- TV-Cons-Chk
  deftc check(ctx, env, st, [_ | _] = xs, {:list, ty} = t) do
    {[v | vs], tail} = normalise_list_shapes(xs)

    tcm env: env, st: st do
      chk(ctx, v, ty) |> with_frame({:list_element, 1})

      chain(vs |> Enum.with_index(2), fn {v, i} ->
        chk(ctx, v, ty) |> with_frame({:list_element, i})
      end)

      chk(ctx, tail, t) |> with_frame(:list_tail)

      ok(t)
    end
  end

  # Map Record Update %{m | k1: v1, ...}
  # no check rule of its own: synthesise and compare (TV-Switch)
  # must come before TV-Record-Chk and TV-Dict-Chk, whose heads also match it
  deftc check(ctx, env, st, {:%{}, _, [{:|, _, [_map_ast, updates]}]} = ast, t)
        when is_list(updates),
        do: switch(ctx, env, st, ast, t)

  # -- TV-Record-Chk
  # Record Construction %{k1: v1, ...}
  deftc check(ctx, env, st, {:%{}, meta, pairs}, {:map_record, types} = t) do
    tcm env: env, st: st do
      # keys that aren't labels are reported by the `chain` below
      labels = for {k, _} <- pairs, is_label(k), do: k
      duplicates = labels -- Enum.uniq(labels)

      expect duplicates == [],
        else: Error.TypeMismatch.record_duplicate_label(ctx.module, meta, hd(duplicates))

      chain(pairs, fn {k, v_ast} ->
        tcm do
          expect is_atom(k),
            else: Error.PatternMatching.complex_map_key(ctx.module, meta, k)

          expect is_label(k),
            else: Error.TypeMismatch.invalid_record_label(ctx.module, meta, k)

          expect {:ok, v_ty} = Map.fetch(types, k),
            else: Error.TypeMismatch.record_unexpected_field(ctx.module, meta, k, t)

          chk(ctx, v_ast, v_ty) |> with_frame({:record_field, k})

          ok()
        end
      end)

      # every label is now known to be one of the type's, so whatever the type has left over is missing
      missing = types |> Map.drop(labels) |> Map.keys() |> Enum.sort()

      expect missing == [],
        else: Error.TypeMismatch.record_missing_fields(ctx.module, meta, missing, t)

      ok(t)
    end
  end

  # -- TV-Dict-Chk
  # Dictionary Construction %{k1 => v1, ...}
  deftc check(ctx, env, st, {:%{}, _meta, pairs}, {:map_dict, {k_ty, v_ty}} = t) do
    # todo: should probably update the ctx.meta with this meta...
    tcm env: env, st: st do
      chain(pairs |> Enum.with_index(1), fn {{k_i, v_ast_i}, i} ->
        tcm do
          chk(ctx, k_i, k_ty) |> with_frame({:dict_key, i})
          chk(ctx, v_ast_i, v_ty) |> with_frame({:dict_value, i})
          ok()
        end
      end)

      ok(t)
    end
  end

  # -- TV-Abs
  # Anonymous Function fn x1, ..., xn -> body end
  # todo: there is no function type in `Types.T` yet, `{:function, param_types, return_type}` is a placeholder
  deftc check(
          ctx,
          env,
          st,
          {:fn, meta, [{:->, _, [params, body_ast]}]},
          {:function, param_types, return_type} = t
        )
        when is_list(params) do
    # todo: later
  end

  # -- TV-Switch
  deftc check(ctx, env, st, ast, t), do: switch(ctx, env, st, ast, t)

  defp switch(ctx, env, st, ast, t) do
    # todo: clean this up
    meta = Helpers.extract_meta_from_ast(ast)
    meta = if Keyword.has_key?(meta, :line), do: meta, else: ctx.meta

    tcm env: env, st: st do
      t2 <- syn(ctx, ast)
      expect t2 == t, else: Error.TypeMismatch.expected(ctx.module, meta, expected: t, got: t2)
      ok(t)
    end
  end
end
