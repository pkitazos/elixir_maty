defmodule Maty.Typechecker.TC do
  require Logger

  alias Maty.ST.SBottom
  alias Maty.{Check, Types}
  alias Maty.Typechecker.{Error, Helpers, TC, Ctx}

  import Maty.Check
  import Maty.Utils, only: [deftc: 2]

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
  @spec tc_expr(Ctx.t(), Check.var_env(), Maty.ST.t(), ast()) :: result()

  # -- Val-BaseLit
  deftc tc_expr(_ctx, env, st, value) when is_boolean(value) do
    {:ok, :boolean, st, env}
  end

  deftc tc_expr(_ctx, env, st, falsy_guard()) do
    {:ok, :boolean, st, env}
  end

  deftc tc_expr(_ctx, env, st, nil) do
    {:ok, nil, st, env}
  end

  deftc tc_expr(_ctx, env, st, value) when is_binary(value) do
    {:ok, :binary, st, env}
  end

  deftc tc_expr(_ctx, env, st, value) when is_number(value) do
    {:ok, :number, st, env}
  end

  deftc tc_expr(_ctx, env, st, {:%, _, [Date, {:%{}, _, _}]}) do
    {:ok, :date, st, env}
  end

  # -- Val-EmptyList
  deftc tc_expr(_ctx, env, st, []) do
    {:ok, {:list, :any}, st, env}
  end

  # -- Val-Cons
  # List Construction [v1, v2, ...]
  # Enforces homogeneity. Preserves session state.
  deftc tc_expr(ctx, env, st, items) when is_list(items) do
    check env: env, st: st do
      list_types <- chain(items, &tc(ctx, &1))

      expect {:ok, type} = Helpers.unify_list_types(list_types),
        else: Error.TypeMismatch.list_elements_incompatible(ctx.module, ctx.meta, list_types)

      ok({:list, type})
    end
  end

  # -- Val-EmptyTuple
  # Empty Tuple Construction
  deftc tc_expr(_ctx, env, st, {:{}, _, []}) do
    {:ok, {:tuple, []}, st, env}
  end

  # -- Val-Tuple
  # 2-Tuple Value Construction
  deftc tc_expr(ctx, env, st, {lhs_ast, rhs_ast}) do
    check env: env, st: st do
      lhs_type <- tc(ctx, lhs_ast)
      rhs_type <- tc(ctx, rhs_ast)
      ok({:tuple, [lhs_type, rhs_type]})
    end
  end

  # -- Val-Tuple
  # n-Tuple Construction {v1, v2, ...}
  deftc tc_expr(ctx, var_env, st_pre, {:{}, _, items}) when is_list(items) do
    check env: var_env, st: st_pre do
      types <- chain(items, &tc(ctx, &1))
      ok({:tuple, types})
    end
  end

  # Map Record Update %{m | k1: v1, ...}
  # every key must already be in the record and keep its field's type, so the result has the record's type
  # (at runtime `|` raises a KeyError for a missing key, so an update can never add a key)
  deftc tc_expr(ctx, env, st, {:%{}, meta, [{:|, _, [map_ast, updates]}]})
        when is_list(updates) do
    check env: env, st: st do
      map_type <- tc(ctx, map_ast)

      expect {:map_record, fields} = map_type,
        else: Error.TypeMismatch.map_update_not_record(ctx.module, meta, got: map_type)

      chain(updates, fn {key_ast, val_ast} ->
        check do
          # keys must be literal atoms, a record's fields are known statically
          expect is_atom(key_ast),
            else: Error.PatternMatching.complex_map_key(ctx.module, meta, key_ast)

          key = key_ast

          expect {:ok, field_type} = Map.fetch(fields, key),
            else: Error.TypeMismatch.map_update_key_not_found(ctx.module, meta, key, map_type)

          val_type <- tc(ctx, val_ast)

          expect val_type == field_type,
            else:
              Error.TypeMismatch.map_update_value_type_mismatch(ctx.module, meta, key,
                expected: field_type,
                got: val_type
              )

          ok()
        end
      end)

      ok(map_type)
    end
  end

  # Map Construction %{k1 => v1, ...} (Val-Map)
  deftc tc_expr(ctx, env, st, {:%{}, meta, pairs}) do
    check env: env, st: st do
      fields <-
        chain(pairs, fn {key_ast, val_ast} ->
          check do
            # keys must be literal atoms, a record's fields are known statically
            expect is_atom(key_ast),
              else: Error.PatternMatching.complex_map_key(ctx.module, meta, key_ast)

            val_type <- tc(ctx, val_ast)

            ok({key_ast, val_type})
          end
        end)

      ok({:map_record, Map.new(fields)})
    end
  end

  # Map Record Field Access m.k
  # expanded AST: {{:., _, [map_ast, key]}, [no_parens: true, ...], []}
  # a zero-arity remote call `Mod.fun()` has the same shape, but its left-hand side is always a module atom
  deftc tc_expr(ctx, env, st, {{:., meta, [map_ast, key]}, _call_meta, []})
        when not is_atom(map_ast) and is_atom(key) do
    check env: env, st: st do
      map_type <- tc(ctx, map_ast)

      expect {:map_record, fields} = map_type,
        else: Error.TypeMismatch.field_access_not_record(ctx.module, meta, got: map_type)

      expect {:ok, val_type} = Map.fetch(fields, key),
        else: Error.TypeMismatch.field_access_key_not_found(ctx.module, meta, key, map_type)

      ok(val_type)
    end
  end

  # -- T-Not
  deftc tc_expr(ctx, env, st, erlang(:not, meta, [operand_ast])) do
    check env: env, st: st do
      res_type <- tc(ctx, operand_ast)

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
  deftc tc_expr(ctx, env, st, erlang(:-, meta, [operand_ast])) do
    check env: env, st: st do
      operand_type <- tc(ctx, operand_ast)

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
  deftc tc_expr(ctx, env, st, erlang(erlang_op, meta, [lhs_ast, rhs_ast]))
        when erlang_op in [:+, :-, :*, :/, :<, :>, :"=<", :>=, :==, :"/="] do
    op = Map.get(@source_ops, erlang_op, erlang_op)

    check env: env, st: st do
      lhs_type <- tc(ctx, lhs_ast)
      rhs_type <- tc(ctx, rhs_ast)

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
  deftc tc_expr(ctx, env, st, {:<<>>, meta, segments}) when is_list(segments) do
    check env: env, st: st do
      _ <- chain(segments, &tc_string_segment(ctx, meta, &1))
      ok(:binary)
    end
  end

  # Handles Boolean Ops: and, or
  # matched in the `case` they expand to (see `boolean_op/4`)
  deftc tc_expr(ctx, env, st, boolean_op(:and, meta, lhs_ast, rhs_ast)) do
    tc_boolean_op(ctx, env, st, :and, meta, lhs_ast, rhs_ast)
  end

  deftc tc_expr(ctx, env, st, boolean_op(:or, meta, lhs_ast, rhs_ast)) do
    tc_boolean_op(ctx, env, st, :or, meta, lhs_ast, rhs_ast)
  end

  # rejected cause they're annoying to type
  deftc tc_expr(ctx, env, _st, truthy_op(:&&, meta)) do
    {:error, Error.FrameworkUsage.unsupported_truthy_operator(ctx.module, meta, :&&), env}
  end

  deftc tc_expr(ctx, env, _st, truthy_op(:||, meta)) do
    {:error, Error.FrameworkUsage.unsupported_truthy_operator(ctx.module, meta, :||), env}
  end

  # Raw Communication Checks

  # Disallow raw 'receive'
  deftc tc_expr(ctx, env, _st, {:receive, meta, _}) do
    {:error, Error.FrameworkUsage.no_native_receive(ctx.module, meta), env}
  end

  # Disallow raw 'send' (Kernel.send/2 or :erlang.send/2)
  deftc tc_expr(ctx, env, _st, erlang(:send, meta, args))
        when length(args) in [2, 3] do
    {:error, Error.FrameworkUsage.no_native_send(ctx.module, meta), env}
  end

  # Anonymous Functions and Captures
  # not supported: would require either type annotations (which do not exist in the language in any capacity)
  # or type inference (which was not really the point of this project)
  # Reject them explicitly so they do not fall through to T-App

  # Anonymous function: fn args -> ... end
  deftc tc_expr(ctx, env, _st, {:fn, meta, _clauses}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # todo: not really anonymus is it?
  # Function capture: &Mod.fun/arity, &fun/arity, &(&1 + 1)
  deftc tc_expr(ctx, env, _st, {:&, meta, [_capture]}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # Block Scope
  deftc tc_expr(ctx, var_env, st_pre, {:__block__, _, body_asts}) when is_list(body_asts) do
    tc_expr_list(ctx, var_env, st_pre, body_asts)
  end

  # Computation Typing

  # -- T-Let
  deftc tc_expr(ctx, env, st, {:=, _meta, [pat_ast, expr_ast]}) do
    check env: env, st: st do
      expr_type <- tc(ctx, expr_ast)
      _ <- match_pattern(ctx, pat_ast, expr_type)
      ok(expr_type)
    end
  end

  # -- T-Case
  # todo: revisit this
  deftc tc_expr(ctx, env, st, {:case, meta, [scrutinee_ast, [do: clauses_list]]}) do
    check env: env, st: st do
      scrutinee_type <- tc(ctx, scrutinee_ast)

      branch_results <-
        fan_out(Enum.with_index(clauses_list, 1), fn
          {{:->, branch_meta, [[pat_ast], expr_ast]}, index} ->
            check do
              # a literal pattern has no meta of its own, so its errors are reported at the branch
              _ <- match_pattern(%{ctx | meta: branch_meta}, pat_ast, scrutinee_type)
              tc(ctx, expr_ast)
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
  deftc tc_expr(
          ctx,
          env,
          st_pre,
          maty_runtime(:send_session_message, meta, [_, recipient_ast, message_ast])
        ) do
    check env: env, st: st_pre do
      # the message must be a literal 2-tuple
      expect {literal_label, payload_expr_ast} = message_ast,
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      # the label of a message, must be an atom
      expect is_atom(literal_label),
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      actual_payload_type <- tc(ctx, payload_expr_ast)

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

  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [IO, _]}, _, _} = ast) do
    TC.IO.tc_expr(ctx, var_env, st_pre, ast)
  end

  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [:timer, _]}, _, _} = ast) do
    TC.Timer.tc_expr(ctx, var_env, st_pre, ast)
  end

  # -- T-Suspend
  deftc tc_expr(
          ctx,
          env,
          st,
          maty_runtime(:suspend, meta, [handler_ast, state_ast])
        ) do
    check env: env, st: st do
      # TV-MsgHandler
      # instead of typing the handler name as a value, the literal atom is checked against Δ_M directly
      expect Map.has_key?(ctx.delta_M, handler_ast),
        else:
          Error.ProtocolViolation.suspend_invalid_handler_type(
            ctx.module,
            meta,
            [got: handler_ast],
            st
          )

      state_type <- tc(ctx, state_ast)

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

      expect expected_handler == handler_ast,
        else:
          Error.ProtocolViolation.incorrect_handler_suspension(
            ctx.module,
            meta,
            q,
            got: handler_ast,
            expected: expected_handler
          )

      ok(:no_return, st: %SBottom{reason: :suspend})
    end
  end

  # -- T-Done
  deftc tc_expr(
          ctx,
          env,
          st,
          maty_runtime(:done, meta, [state_ast])
        ) do
    check env: env, st: st do
      state_type <- tc(ctx, state_ast)

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
  deftc tc_expr(
          ctx,
          env,
          st,
          maty_runtime(:register, meta, [
            ap_pid_ast,
            role_ast,
            handler_name,
            args_ast
          ])
        )
        when is_atom(handler_name) do
    check env: env, st: st do
      pid_type <- tc(ctx, ap_pid_ast)

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

      # TV-InitHandler
      # instead of typing the handler name as a value, the literal atom is checked against Δ_I directly
      expect {:ok, accepted_arg_types} = Helpers.init_handler_arg_types(ctx, handler_name),
        else:
          Error.FrameworkUsage.unknown_init_handler(
            ctx.module,
            meta,
            handler_name,
            Map.keys(ctx.delta_I)
          )

      args_type <- tc(ctx, args_ast)

      expect accepted_arg_types == [] or args_type in accepted_arg_types,
        else:
          Error.TypeMismatch.register_arg_type_mismatch(
            ctx.module,
            meta,
            :init_handler_args,
            expected: accepted_arg_types,
            got: args_type
          )

      ok(:atom)
    end
  end

  deftc tc_expr(
          ctx,
          env,
          _st,
          maty_runtime(:register, meta, [_, _, handler_ast, _])
        ) do
    {:error, Error.FrameworkUsage.init_handler_not_literal(ctx.module, meta, handler_ast), env}
  end

  deftc tc_expr(
          ctx,
          env,
          _st,
          {{:., _m1, [Maty.DSL, :register]}, meta, args}
        ) do
    # function is called with the wrong number of args
    # todo: maybe not necessary?
    {:error, Error.FrameworkUsage.register_wrong_arity(ctx.module, meta, length(args)), env}
  end

  # -- T-App
  # todo: how could I handle remote calls?
  deftc tc_expr(ctx, env, st, {func_name, meta, arg_asts})
        when is_atom(func_name) and is_list(arg_asts) and meta != [] and
               func_name not in [:=, :%, :{}, :|, :<<>>] do
    func_id = {func_name, length(arg_asts)}

    check env: env, st: st do
      expect not Map.has_key?(ctx.delta_M, func_name),
        else: Error.FunctionCall.handler_called_directly(ctx.module, meta, func_id, :message)

      expect not Map.has_key?(ctx.delta_I, func_name),
        else: Error.FunctionCall.handler_called_directly(ctx.module, meta, func_id, :init)

      expect {:ok, signatures} = Map.fetch(ctx.psi, func_id),
        else: Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)

      expect signatures != [],
        else: Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)

      arg_types <-
        arg_asts
        |> chain(&tc(ctx, &1))
        |> with_frame({:call, func_id, Keyword.take(meta, [:line, :column])})

      # todo: this accepts the call if the arguments fit *any* clause's spec, but at runtime the
      # first clause whose *pattern* matches is the one that runs. With overlapping patterns and
      # different specs, a call can be accepted against one clause and run another.
      # Should instead pick the first clause whose pattern matches the argument types and check against its spec only
      # (this would need access to the clause patterns here, psi currently only has the specs).
      # Same issue in `Helpers.init_handler_arg_types/2` for register
      expect {_, return_type} =
               Enum.find(signatures, fn {param_types, _} -> arg_types == param_types end),
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
  deftc tc_expr(ctx, env, st, {var_name, meta, nil}) when is_atom(var_name) do
    case Map.fetch(env, var_name) do
      {:ok, type} ->
        {:ok, type, st, env}

      :error ->
        {:error, Error.NameResolution.variable_not_exist(ctx.module, meta, var_name), env}
    end
  end

  # -- Val-BaseLit (I gotta do something about these names..)
  # Atom literals
  deftc tc_expr(_ctx, env, st, value) when is_atom(value) and not is_nil(value) do
    {:ok, :atom, st, env}
  end

  # Catch-all: anything no rule above covers is reported
  deftc tc_expr(ctx, env, _st, ast) do
    meta = Helpers.extract_meta_from_ast(ast)
    meta = if Keyword.has_key?(meta, :line), do: meta, else: ctx.meta
    {:error, Error.FrameworkUsage.unsupported_expression(ctx.module, meta, ast), env}
  end

  # types that String.Chars implements
  @interpolatable_types [:atom, :binary, :boolean, :date, :number, nil]

  # an interpolated value: `String.Chars.to_string(x) :: binary`
  defp tc_string_segment(
         ctx,
         meta,
         {:"::", seg_meta, [{{:., _, [String.Chars, :to_string]}, _, [val_ast]}, {:binary, _, _}]}
       ) do
    check do
      val_type <- tc(ctx, val_ast)

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
    check do
      val_type <- tc(ctx, val_ast)

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
    check env: env, st: st do
      lhs_type <- tc(ctx, lhs_ast)
      rhs_type <- tc(ctx, rhs_ast)

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

  # Processes a list of expressions sequentially using tc_expr.
  # Returns the result of the *last* expression in the list.
  # the only reason this isn't inlined is because it's used in a bunch of places in the wf module
  @spec tc_expr_list(Ctx.t(), Check.var_env(), Maty.ST.t(), [ast()]) :: result()
  def tc_expr_list(ctx, var_env, st_pre, ast_list) do
    check env: var_env, st: st_pre do
      types <- chain(ast_list, &tc(ctx, &1))
      ok(List.last(types))
    end
  end
end
