defmodule Maty.Typechecker.TC do
  require Logger

  alias Maty.Check
  import Maty.Check

  alias Maty.ST.SBottom
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{Error, Helpers, TC, Ctx}

  import Maty.Utils, only: [deftc: 2]

  @typedoc """
  Represents Elixir AST nodes that can be typechecked.
  """
  @type ast :: Macro.t()

  @type var_env :: Check.var_env()
  @type result :: Check.result(Type.t())

  @doc """
  Typechecks an expression AST node within a given variable environment and
  session state pre-condition.

  Corresponds to the formal judgement: Ψ; Δ; Γ ∣ Q₁ ⊳ e : T ⊲ Q₂

  Returns:
    - `{:ok, elixir_type, next_session_state, var_env}` on success
    - `{:error, error, var_env}` on failure
  """
  @spec tc_expr(Ctx.t(), var_env(), Maty.ST.t(), ast()) :: result()

  # -- Val-BaseLit
  deftc tc_expr(_ctx, env, st, value) when is_boolean(value) do
    {:ok, :boolean, st, env}
  end

  deftc tc_expr(
          _ctx,
          env,
          st,
          {:when, _,
           [
             {:x, _, Kernel},
             {{:., _, [:erlang, :orelse]}, _,
              [
                {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, false]},
                {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, nil]}
              ]}
           ]}
        ) do
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

  deftc tc_expr(_ctx, env, st, value) when is_pid(value) do
    {:ok, :pid, st, env}
  end

  deftc tc_expr(_ctx, env, st, value) when is_reference(value) do
    {:ok, :ref, st, env}
  end

  deftc tc_expr(_ctx, env, st, {:%, _, [Date, {:%{}, _, _}]}) do
    {:ok, :date, st, env}
  end

  deftc tc_expr(_ctx, env, st, {{:., _, [{:__aliases__, _, [:Date]}, :t]}, _, []}) do
    {:ok, :date, st, env}
  end

  deftc tc_expr(_ctx, env, st, {:no_return, _meta, []}) do
    {:ok, :no_return, st, env}
  end

  deftc tc_expr(_ctx, env, st, {:any, _meta, []}) do
    {:ok, :any, st, env}
  end

  # List Construction [v1, v2, ...] (Val-Cons / Val-EmptyList adaptation)
  # Enforces homogeneity. Preserves session state.
  deftc tc_expr(_ctx, env, st, []) do
    {:ok, {:list, :any}, st, env}
  end

  deftc tc_expr(ctx, env, st, items) when is_list(items) do
    check env: env, st: st do
      list_types <- chain(items, &tc(ctx, &1))

      expect {:ok, type} = Helpers.unify_list_types(list_types),
        else: Error.TypeMismatch.list_elements_incompatible(ctx.module, ctx.meta, list_types)

      ok({:list, type})
    end
  end

  # Empty Tuple (Val-EmptyTuple adaptation)
  # Preserves session state.
  deftc tc_expr(_ctx, env, st, {:{}, _, []}) do
    {:ok, {:tuple, []}, st, env}
  end

  # --- 2-Tuple Value Construction ---
  # Handles literal 2-tuples {v1, v2} explicitly, distinct from n-tuples {:{}, _, [...]} in the AST
  deftc tc_expr(ctx, env, st, {lhs_ast, rhs_ast}) do
    check env: env, st: st do
      lhs_type <- tc(ctx, lhs_ast)
      rhs_type <- tc(ctx, rhs_ast)
      ok({:tuple, [lhs_type, rhs_type]})
    end
  end

  # n-Tuple Construction {v1, v2, ...} (Val-Tuple adaptation)
  # Preserves session state.
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
          # (a variable or call key is a 3-tuple in the AST, so only a literal atom passes `is_atom`)
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
          # ^ why is my editor complaining about this
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
            # (a variable or call key is a 3-tuple in the AST, so only a literal atom passes `is_atom`)
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

  # --- Logical Not Operator (T-Not) ---

  deftc tc_expr(ctx, env, st, {{:., meta, [:erlang, :not]}, _, [operand_ast]}) do
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

  # --- Binary Operators (T-Op) ---

  # Handles Arithmetic and Comparison Ops: +, -, *, /, <, >, <=, >=, ==, !=
  deftc tc_expr(ctx, env, st, {{:., meta, [:erlang, op]}, _, [lhs_ast, rhs_ast]})
        when op in [:+, :-, :*, :/, :<, :>, :<=, :>=, :==, :!=] do
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

  # --- Strings: Concatenation and Interpolation ---
  # after expansion both `"a" <> b <> "c"` and `"a=#{n}"` are a single `<<>>` with one `segment :: binary` per part
  # Other bitstring syntax (sizes, integer segments, ...) is not supported
  deftc tc_expr(ctx, env, st, {:<<>>, meta, segments}) when is_list(segments) do
    check env: env, st: st do
      _ <- chain(segments, &tc_string_segment(ctx, meta, &1))
      ok(:binary)
    end
  end

  # Handles Boolean Ops: and, or
  deftc tc_expr(ctx, env, st, {op, meta, [lhs_ast, rhs_ast]})
        when op in [:and, :or] do
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

  # --- Raw Communication Checks ---

  # Disallow raw 'receive'
  deftc tc_expr(ctx, env, _st, {:receive, meta, _}) do
    {:error, Error.FrameworkUsage.no_native_receive(ctx.module, meta), env}
  end

  # Disallow raw 'send' (Kernel.send/2 or :erlang.send/2)
  deftc tc_expr(ctx, env, _st, {{:., meta, [:erlang, :send]}, _, args})
        when length(args) in [2, 3] do
    {:error, Error.FrameworkUsage.no_native_send(ctx.module, meta), env}
  end

  # Check for Kernel.send/2
  deftc tc_expr(ctx, env, _st, {{:., meta, [:Kernel, :send]}, _, args})
        when length(args) == 2 do
    {:error, Error.FrameworkUsage.no_native_send(ctx.module, meta), env}
  end

  # --- Anonymous Functions and Captures ---
  # not supported: would require either type annotations (which do not exist in the language in any capacity)
  # or type inference (which was not really the point of this project)
  # Reject them explicitly so they do not fall through to T-App

  # Anonymous function: fn args -> ... end
  deftc tc_expr(ctx, env, _st, {:fn, meta, _clauses}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # Function capture: &Mod.fun/arity, &fun/arity, &(&1 + 1)
  deftc tc_expr(ctx, env, _st, {:&, meta, [_capture]}) do
    {:error, Error.FrameworkUsage.unsupported_anonymous_function(ctx.module, meta), env}
  end

  # --- Block Scope ---
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

  # --- Case Expression (T-Case) ---
  # todo: revisit this
  deftc tc_expr(ctx, env, st, {:case, meta, [scrutinee_ast, [do: clauses_list]]}) do
    check env: env, st: st do
      scrutinee_type <- tc(ctx, scrutinee_ast)
      # idk if I even _should_ check that the scrutinee didn't change the type of the session type
      # it feels like such an arbitrary restriction

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

  # --- Maty Send Operation (T-Send) ---
  # Matches call to Maty.DSL.internal_send/3 which the send/2 macro expands to
  deftc tc_expr(
          ctx,
          env,
          st_pre,
          {{:., meta, [Maty.Runtime, :send_session_message]}, _,
           [_session_ctx, recipient_ast, message_ast]}
        ) do
    check env: env, st: st_pre do
      expect_st %ST.SOut{to: expected_role, branches: branches},
        else: fn st ->
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: {:send, [recipient_ast, message_ast]}],
            st
          )
        end

      _recipient_type <- value(ctx, recipient_ast, meta)

      # roles must be literal atoms, choosing a branch of the session type is static
      expect is_atom(recipient_ast),
        else: Error.FrameworkUsage.role_not_literal(ctx.module, meta, recipient_ast)

      expect recipient_ast == expected_role,
        else:
          Error.ProtocolViolation.incorrect_target_participant(
            ctx.module,
            meta,
            st_pre,
            got: recipient_ast,
            expected: expected_role
          )

      # Check message structure {label, payload_expr}
      # the message must be a literal 2-tuple with a literal atom label, for the same reason as the role
      # (calls, variables and n-tuples are all 3-tuples in the AST, so only a literal 2-tuple matches)
      expect {literal_label, payload_expr_ast} = message_ast,
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      # the label of a message, must be an atom
      expect is_atom(literal_label),
        else: Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: message_ast)

      # Typecheck payload expression
      actual_payload_type <- value(ctx, payload_expr_ast, meta)

      case Helpers.try_get_matching_branch(branches, literal_label, actual_payload_type) do
        {:ok, branch} ->
          ok(:atom, st: branch.continue_as)

        {:error, :label_mismatch} ->
          fail(
            Error.ProtocolViolation.incorrect_message_label(
              ctx.module,
              meta,
              st_pre,
              got: literal_label,
              expected: Enum.map(branches, & &1.label)
            )
          )

        {:error, :payload_mismatch, branch} ->
          fail(
            Error.ProtocolViolation.incorrect_payload_type(
              ctx.module,
              meta,
              st_pre,
              got: actual_payload_type,
              expected: branch.payload
            )
          )
      end
    end
  end

  # I really do not like these 2

  # --- IO ---
  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [IO, _]}, _, _} = ast) do
    TC.IO.tc_expr(ctx, var_env, st_pre, ast)
  end

  # --- :timer ---
  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [:timer, _]}, _, _} = ast) do
    TC.Timer.tc_expr(ctx, var_env, st_pre, ast)
  end

  # So, what if..
  # rather than enforcing that nothing can update the session type while typechecking a suspend or send or whatever,
  # what if we typecheck normally, allowing any expression to progress the ST, up until we've typechecked every sub-expression
  # and only right before we only have the send/suspend/whatever to "check" onlt then do we error if the st is not in the right state

  # --- Maty Suspend Operation (T-Suspend) ---
  # Matches throw({:suspend, handler, state}) from Maty.DSL.suspend/2
  # todo: update doc comment
  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _, [Maty.Runtime, :suspend]}, meta, [handler_ast, state_ast]}
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

      state_type <- value(ctx, state_ast, meta)

      expect state_type == Type.maty_actor_state(),
        else:
          Error.TypeMismatch.invalid_maty_state_type(
            ctx.module,
            meta,
            Error.TypeMismatch.invalid_maty_state_cause(state_type)
          )

      expect_st %ST.SName{handler: expected_handler},
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
            st,
            got: handler_ast,
            expected: expected_handler
          )

      ok(:no_return, st: %SBottom{reason: :suspend})
    end
  end

  # --- Maty Done Operation (T-Done) ---
  # Matches throw({:done, state}) from Maty.DSL.done/1
  # AST: {:throw, meta, [{:done, state_ast}]}

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _, [Maty.Runtime, :done]}, meta, [state_ast]}
        ) do
    check env: env, st: st do
      state_type <- value(ctx, state_ast, meta)

      expect state_type == Type.maty_actor_state(),
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

  # --- Maty Register Operation (T-Register) ---
  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _m1, [Maty.Runtime, :register]}, meta,
           [ap_pid_ast, role_ast, handler_name, args_ast, local_state_ast]}
        )
        when is_atom(handler_name) do
    check env: env, st: st do
      pid_type <- value(ctx, ap_pid_ast, meta)

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

      # todo: come back once register API is settled
      _local_state_type <- tc(ctx, local_state_ast)

      ok(:atom)
    end
  end

  deftc tc_expr(
          ctx,
          env,
          _st,
          {{:., _m1, [Maty.Runtime, :register]}, meta,
           [_ap_pid_ast, _role_ast, handler_ast, _args_ast, _local_state_ast]}
        ) do
    # `handler_name` is not an atom
    {:error, Error.FrameworkUsage.init_handler_not_literal(ctx.module, meta, handler_ast), env}
  end

  deftc tc_expr(
          ctx,
          env,
          _st,
          {{:., _m1, [Maty.DSL, :register]}, meta, args}
        ) do
    # function is called with the wrong number of args
    {:error, Error.FrameworkUsage.register_wrong_arity(ctx.module, meta, length(args)), env}
  end

  # --- Function Application (T-App) ---
  # Handles local function calls: f(arg1, arg2, ...)
  deftc tc_expr(ctx, env, st, {func_name, meta, arg_asts})
        when is_atom(func_name) and is_list(arg_asts) and meta != [] and
               func_name not in [:=, :%, :{}, :|, :<<>>] do
    func_id = {func_name, length(arg_asts)}

    check env: env, st: st do
      expect {:ok, signatures} = Map.fetch(ctx.psi, func_id),
        else: Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)

      expect signatures != [],
        else: Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)

      arg_types <- chain(arg_asts, &tc(ctx, &1))

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
  deftc tc_expr(ctx, env, st, {var_name, meta, context})
        when is_atom(var_name) and (is_nil(context) or is_list(context)) do
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

  # Processes a list of expressions sequentially using tc_expr.
  # Returns the result of the *last* expression in the list.
  # the only reason this isn't inlined is because it's used in a bunch of places in the wf module
  @spec tc_expr_list(Ctx.t(), var_env(), Maty.ST.t(), [ast()]) :: result()
  def tc_expr_list(ctx, var_env, st_pre, ast_list) do
    check env: var_env, st: st_pre do
      types <- chain(ast_list, &tc(ctx, &1))
      ok(List.last(types))
    end
  end
end
