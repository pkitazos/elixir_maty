defmodule Maty.Typechecker.TC do
  require Logger

  import Maty.Typechecker.TC.Thread
  alias Maty.ST
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{Error, Helpers, TC, Ctx, Judgment}

  import Maty.Typechecker.TC.Bind
  import Maty.Typechecker.PatternBinding, only: [tc_pattern: 4]
  import Maty.Utils, only: [deftc: 2]

  @typedoc """
  Represents Elixir AST nodes that can be typechecked.
  """
  @type ast :: Macro.t()

  @type var_env :: Judgment.var_env()
  @type result :: Judgment.result()

  @doc """
  Typechecks an expression AST node within a given variable environment and
  session state pre-condition.

  Corresponds to the formal judgement: Ψ; Δ; Γ ∣ Q₁ ⊳ e : T ⊲ Q₂

  Returns:
    - `{:ok, elixir_type, next_session_state, var_env}` on success
    - `{:error, error_message, var_env}` on failure
  """
  @spec tc_expr(ctx :: Ctx.t(), var_env :: var_env(), st_pre :: ST.t(), ast :: ast()) ::
          result()

  # --- Revised Value Typing Clauses ---

  # Base Literals (Val-BaseLit adaptation)
  # These are pure values; they preserve the current session state.
  deftc tc_expr(_ctx, env, st, value) when is_boolean(value) do
    ok(:boolean, env, st)
  end

  def tc_expr(
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
    ok(:boolean, env, st)
  end

  deftc tc_expr(_ctx, env, st, nil) do
    ok(nil, env, st)
  end

  deftc tc_expr(_ctx, env, st, value) when is_binary(value) do
    ok(:binary, env, st)
  end

  deftc tc_expr(_ctx, env, st, value) when is_number(value) do
    ok(:number, env, st)
  end

  deftc tc_expr(_ctx, env, st, value) when is_pid(value) do
    ok(:pid, env, st)
  end

  deftc tc_expr(_ctx, env, st, value) when is_reference(value) do
    ok(:ref, env, st)
  end

  deftc tc_expr(_ctx, env, st, {:%, _, [Date, {:%{}, _, _}]}) do
    ok(:date, env, st)
  end

  deftc tc_expr(_ctx, env, st, {{:., _, [{:__aliases__, _, [:Date]}, :t]}, _, []}) do
    ok(:date, env, st)
  end

  deftc tc_expr(_ctx, env, st, {:no_return, _meta, []}) do
    ok(:no_return, env, st)
  end

  deftc tc_expr(_ctx, env, st, {:any, _meta, []}) do
    ok(:any, env, st)
  end

  # todo: either add support for keyword lists or make this just work properly
  # as in this part of the register macro could either straight up expand to an anonymous function
  # or it could require a list of 2-tuples where
  # the first element is a tagged tuple containing an atom which maps to a handler
  # and the second element is a tagged tuple containing a list of arguments of whatever type
  # and the types need to match the type of the handler somehow?

  # --- Init Handler reference (Keyword list is technically a List)---
  # Handles passing a reference to an init_handler when registering
  deftc tc_expr(ctx, env, st, [callback: init_handler, args: args_ast] = _ast)
        when is_list(args_ast) do
    if Map.has_key?(ctx.delta_I, init_handler) do
      ok({:fun, length(args_ast)}, env, st)
    else
      # pin - convert to new kind of error
      error("Trying to register with invalid init_handler", env)
    end
  end

  deftc tc_expr(ctx, env, st, [callback: init_handler, args: args_ast] = _ast)
        when is_nil(args_ast) do
    if Map.has_key?(ctx.delta_I, init_handler) do
      ok({:fun, 0}, env, st)
    else
      # pin - convert to new kind of error
      error("Trying to register with invalid init_handler", env)
    end
  end

  deftc tc_expr(ctx, env, st, [callback: init_handler] = _ast) do
    if Map.has_key?(ctx.delta_I, init_handler) do
      ok({:fun, 0}, env, st)
    else
      # pin - convert to new kind of error
      error("Trying to register with invalid init_handler", env)
    end
  end

  # List Construction [v1, v2, ...] (Val-Cons / Val-EmptyList adaptation)
  # Enforces homogeneity. Preserves session state.
  deftc tc_expr(_ctx, env, st, []) do
    ok({:list, :any}, env, st)
  end

  deftc tc_expr(ctx, env, st, items) when is_list(items) do
    traverse(items, env, st, fn item, env, st -> tc_expr(ctx, env, st, item) end)
    |> bind(fn list_types, env, st ->
      list_types
      |> Helpers.unify_list_types()
      |> lift_result(
        Error.TypeMismatch.list_elements_incompatible(ctx.module, ctx.meta, list_types),
        env,
        st
      )
    end)
    |> map(fn type -> {:list, type} end)
  end

  # Empty Tuple (Val-EmptyTuple adaptation)
  # Preserves session state.
  deftc tc_expr(_ctx, env, st, {:{}, _, []}) do
    ok({:tuple, []}, env, st)
  end

  # --- 2-Tuple Value Construction ---
  # Handles literal 2-tuples {v1, v2} explicitly, distinct from n-tuples {:{}, _, [...]} in the AST
  deftc tc_expr(ctx, env, st, {v1_ast, v2_ast}) do
    thread do
      v1_t <~ tc_expr(ctx, env, st, v1_ast)
      v2_t <~ tc_expr(ctx, env, st, v2_ast)
      ok({:tuple, [v1_t, v2_t]}, env, st)
    end
  end

  # n-Tuple Construction {v1, v2, ...} (Val-Tuple adaptation)
  # Preserves session state.
  deftc tc_expr(ctx, var_env, st_pre, {:{}, _, items}) when is_list(items) do
    traverse(items, var_env, st_pre, fn item, env, st -> tc_expr(ctx, env, st, item) end)
    |> map(fn types -> {:tuple, types} end)
  end

  # Map Construction %{k1 => v1, ...} (Val-Map / Val-EmptyMap adaptation)
  # Allows heterogeneous value types, deviates slightly from our formalisation
  deftc tc_expr(_ctx, env, st, {:%{}, _, []}) do
    ok({:map, %{}}, env, st)
  end

  # Clause for Non-Empty Map %{k1 => v1, ...}
  deftc tc_expr(ctx, env, st, {:%{}, meta, pairs}) when is_list(pairs) do
    traverse(pairs, env, st, fn {key_ast, val_ast}, env, st ->
      thread do
        key_t <~ tc_expr(ctx, env, st, key_ast)
        _ <~ guard_atom(key_t, meta, ctx, env, st)
        literal_key <~ lift_literal(key_ast, meta, ctx, env, st)
        val_t <~ tc_expr(ctx, env, st, val_ast)
        ok({literal_key, val_t}, env, st)
      end
    end)
    |> map(fn pairs -> {:map, Map.new(pairs)} end)
  end

  # --- Logical Not Operator (T-Not) ---

  deftc tc_expr(ctx, env, st, {{:., meta, [:erlang, :not]}, _, [operand_ast]}) do
    thread do
      result_type <~ tc_expr(ctx, env, st, operand_ast)

      case result_type do
        :boolean ->
          ok(:boolean, env, st)

        other_type ->
          error(
            Error.TypeMismatch.logical_operator_requires_boolean(
              ctx.module,
              meta,
              :not,
              other_type
            ),
            env
          )
      end
    end
  end

  # --- Binary Operators (T-Op) ---

  # Handles Arithmetic and Comparison Ops: +, -, *, /, <, >, <=, >=, ==, !=
  deftc tc_expr(ctx, env, st, {{:., meta, [:erlang, op]}, _, [lhs_ast, rhs_ast]})
        when op in [:+, :-, :*, :/, :<, :>, :<=, :>=, :==, :!=] do
    thread do
      lhs_type <~ tc_expr(ctx, env, st, lhs_ast)
      rhs_type <~ tc_expr(ctx, env, st, rhs_ast)

      lift_result(
        Helpers.op_type_rel(op, lhs_type, rhs_type),
        Error.TypeMismatch.binary_operator_type_mismatch(
          ctx.module,
          meta,
          op,
          lhs_type,
          rhs_type
        ),
        env,
        st
      )
    end
  end

  # Handles String Concatenation: <>

  deftc tc_expr(
          ctx,
          env,
          st,
          {:<<>>, meta, [{:"::", _, [lhs_ast, _]}, {:"::", _, [rhs_ast, _]}]}
        ) do
    thread do
      lhs_type <~ tc_expr(ctx, env, st, lhs_ast)
      rhs_type <~ tc_expr(ctx, env, st, rhs_ast)

      lift_result(
        Helpers.op_type_rel(:<>, lhs_type, rhs_type),
        Error.TypeMismatch.binary_operator_type_mismatch(
          ctx.module,
          meta,
          :<>,
          lhs_type,
          rhs_type
        ),
        env,
        st
      )
    end
  end

  # Handles Boolean Ops: and, or
  deftc tc_expr(ctx, env, st, {op, meta, [lhs_ast, rhs_ast]})
        when op in [:and, :or] do
    thread do
      lhs_type <~ tc_expr(ctx, env, st, lhs_ast)
      rhs_type <~ tc_expr(ctx, env, st, rhs_ast)

      lift_result(
        Helpers.op_type_rel(op, lhs_type, rhs_type),
        Error.TypeMismatch.logical_operator_type_mismatch(
          ctx.module,
          meta,
          op,
          lhs_type,
          rhs_type
        ),
        env,
        st
      )
    end
  end

  # --- Raw Communication Checks ---

  # Disallow raw 'receive'
  deftc tc_expr(_ctx, env, _st, {:receive, meta, _}) do
    # pin - convert to new kind of error
    error(Error.no_raw_receive(meta), env)
  end

  # Disallow raw 'send' (Kernel.send/2 or :erlang.send/2)
  deftc tc_expr(_ctx, env, _st, {{:., meta, [:erlang, :send]}, _, args})
        when length(args) in [2, 3] do
    # pin - convert to new kind of error
    error(Error.no_raw_send(meta), env)
  end

  # Check for Kernel.send/2
  deftc tc_expr(_ctx, env, _st, {{:., meta, [:Kernel, :send]}, _, args})
        when length(args) == 2 do
    # pin - convert to new kind of error
    error(Error.no_raw_send(meta), env)
  end

  # --- Anonymous Functions and Captures ---
  # todo: these are a bit rudimentary
  # for proper typechecking of anonymous functions and/or captures we may need to either introduce more syntax
  # or change the typechecker to use constraints and unification

  # Anonymous function: fn args -> ... end
  deftc tc_expr(_ctx, env, st, {:fn, _meta, [{:->, _, [args_ast, _body_ast]}]}) do
    arity = length(args_ast)
    ok({:fun, arity}, env, st)
  end

  # Remote function capture: &Mod.fun/arity
  deftc tc_expr(
          _ctx,
          env,
          st,
          {:&, _meta, [{:/, _, [{{:., _, [_mod, _fun]}, _, _}, arity]}]}
        )
        when is_integer(arity) do
    ok({:fun, arity}, env, st)
  end

  # Local function capture: &fun/arity
  deftc tc_expr(_ctx, env, st, {:&, _meta, [{:/, _, [fun_atom, arity]}]})
        when is_atom(fun_atom) and is_integer(arity) do
    ok({:fun, arity}, env, st)
  end

  # --- Block Scope ---
  deftc tc_expr(ctx, var_env, st_pre, {:__block__, _, body_asts}) when is_list(body_asts) do
    tc_expr_list(ctx, var_env, st_pre, body_asts)
  end

  # Computation Typing

  # --- Let Expression / Match Operator (T-Let) ---
  # Represents `pattern = expr1`
  deftc tc_expr(ctx, env, st, {:=, _meta, [pattern_ast, expr1_ast]}) do
    thread do
      type_a <~ tc_expr(ctx, env, st, expr1_ast)

      case tc_pattern(ctx, pattern_ast, type_a, env) do
        {:ok, _bindings, env2} -> ok(type_a, env2, st)
        {:error, msg, env2} -> error(msg, env2)
      end
    end
  end

  # --- Case Expression (T-Case) ---
  # AST: {:case, meta, [scrutinee_ast, [do: clauses_list]]}

  deftc tc_expr(ctx, env, st, {:case, meta, [scrutinee_ast, [do: clauses_list]]}) do
    st_pre = st

    tc_expr(ctx, env, st, scrutinee_ast)
    |> bind(fn scrutinee_type, env, st ->
      case Helpers.check_st_unchanged(st_pre, st, meta) do
        :ok ->
          fan_out(clauses_list, env, st_pre, fn {:->, _, [[p_ast], e_ast]}, env, st ->
            thread do
              _ <~ lift_pattern(ctx, p_ast, scrutinee_type, env, st)
              tc_expr(ctx, env, st, e_ast)
            end
          end)
          |> bind(fn branch_results, env, _st ->
            case Helpers.join_branch_results(branch_results) do
              {:ok, {branch_type, joined_st}} ->
                ok(branch_type, env, joined_st)

              {:error, [t1: _b1, t2: _b2] = error_branches} ->
                error(
                  Error.TypeMismatch.case_branches_incompatible_types(
                    ctx.module,
                    meta,
                    error_branches
                  ),
                  env
                )

              {:error, [q1: _b1, q2: _b2] = error_branches} ->
                error(
                  Error.TypeMismatch.case_branches_incompatible_session_states(
                    ctx.module,
                    meta,
                    error_branches
                  ),
                  env
                )
            end
          end)

        {:error, reason} ->
          error(reason, env)
      end
    end)
  end

  # --- Maty Send Operation (T-Send) ---
  # Matches call to Maty.DSL.internal_send/3 which the send/2 macro expands to
  deftc tc_expr(
          ctx,
          var_env,
          st_pre,
          {{:., meta, [Maty.DSL, :internal_send]}, _, [_session_ctx, recipient_ast, message_ast]}
        ) do
    case st_pre do
      %ST.SOut{to: expected_role, branches: branches} ->
        with {:recipient, {:ok, :atom, recipient_st, recipient_env}} <-
               {:recipient, tc_expr(ctx, var_env, st_pre, recipient_ast)},
             # Ensure recipient check pure
             :ok <- Helpers.check_st_unchanged(st_pre, recipient_st, meta),

             # Check recipient matches expected rol
             {:role, [got: ^expected_role, expected: _expected_role], _st} <-
               {:role, [got: recipient_ast, expected: expected_role], recipient_st},

             # 4. Check message structure {label, payload_expr}
             #  pin - standardise helper function APIs
             {:message_ok, literal_label, payload_expr_ast} <-
               Helpers.check_message_structure(ctx, meta, message_ast),

             # Typecheck payload expression
             {:payload, {:ok, actual_payload_type, payload_st, payload_env}} <-
               {:payload, tc_expr(ctx, recipient_env, recipient_st, payload_expr_ast)},

             # 5. Find matching branch for the label
             #  pin - this is really messy
             {:branch, {:ok, matched_branch}, [got: _attempted_match, expected: _branches], _st} <-
               {
                 :branch,
                 Helpers.find_matching_branch(branches, {literal_label, actual_payload_type}),
                 [got: {literal_label, actual_payload_type}, expected: branches],
                 payload_st
               },
             %{payload: expected_payload_type, continue_as: st_Sj} = matched_branch,
             # Ensure payload check pure
             :ok <- Helpers.check_st_unchanged(recipient_st, payload_st, meta),
             # Check payload type matches expected
             # todo: should try have it so that the shape of the data sent to the error branches is a little more standardised / uniform
             {:payload, :ok, _st} <-
               {:payload, Helpers.check_payload_type(actual_payload_type, expected_payload_type),
                payload_st} do
          # All checks passed!
          # Result type is :atom, next session state is st_Sj
          # Use env after payload check
          {:ok, :atom, st_Sj, payload_env}
        else
          {:error, msg, env} ->
            {:error, msg, env}

          {:error, msg} ->
            {:error, msg, var_env}

          {:branch, {:error, :label_mismatch}, [got: {label_received, _}, expected: branches], st} ->
            branch_options = branches |> Enum.map(fn b -> b.label end)

            error_msg =
              Error.ProtocolViolation.incorrect_message_label(ctx.module, meta, st,
                got: label_received,
                expected: branch_options
              )

            {:error, error_msg, var_env}

          # todo: try doing something about this situation. don't wanna have to check twice for the label violations
          {:branch, {:error, :payload_mismatch},
           [got: {label_received, payload_received}, expected: branches], st} ->
            expected_branch =
              branches
              |> Enum.find(fn b -> b.label == label_received end)

            case expected_branch do
              nil ->
                branch_options = branches |> Enum.map(fn b -> b.label end)

                error_msg =
                  Error.ProtocolViolation.incorrect_message_label(
                    ctx.module,
                    meta,
                    st,
                    got: label_received,
                    expected: branch_options
                  )

                {:error, error_msg, var_env}

              other ->
                error_msg =
                  Error.ProtocolViolation.incorrect_payload_type(
                    ctx.module,
                    meta,
                    st,
                    got: payload_received,
                    expected: other.payload
                  )

                {:error, error_msg, var_env}
            end

          {:role, roles, st} ->
            error_msg =
              Error.ProtocolViolation.incorrect_target_participant(ctx.module, meta, st, roles)

            {:error, error_msg, var_env}

          {:payload, payloads, st} ->
            error_msg =
              Error.ProtocolViolation.incorrect_payload_type(ctx.module, meta, st, payloads)

            {:error, error_msg, var_env}

          # todo: fix this it
          {label, e} when label in [:recipient, :message, :branch, :payload] ->
            e
        end

      other_state ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            # todo: try to render shape of message
            [got: "MatyDSL.send(:#{recipient_ast}, message)"],
            other_state
          )

        {:error, error_msg, var_env}
    end
  end

  # --- Maty setState (T-Set) ---
  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., meta, [Maty.DSL.State, :set]}, _,
           [{state_var, _, _} = state_ast, _new_state, _session_ctx]}
        ) do
    thread do
      state_type <~ tc_expr(ctx, env, st, state_ast)

      maty_actor_state_type
      <~ lift_result(
        Helpers.check_maty_state_type(state_type),
        # todo: fix error stuff later
        Error.TypeMismatch.invalid_maty_state_type(
          ctx.module,
          meta,
          Error.TypeMismatch.invalid_maty_state_type(state_type)
        ),
        env,
        st
      )

      ok(maty_actor_state_type, Map.put(env, state_var, maty_actor_state_type), st)
    end
  end

  # --- Maty getState (T-Get) ---
  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., meta, [Maty.DSL.State, :get]}, _, [{state_var, _, _} = state_ast, _session_ctx]}
        ) do
    thread do
      state_type <~ tc_expr(ctx, env, st, state_ast)

      maty_actor_state_type
      <~ lift_result(
        Helpers.check_maty_state_type(state_type),
        Error.TypeMismatch.invalid_maty_state_type(
          ctx.module,
          meta,
          Error.TypeMismatch.invalid_maty_state_type(state_type)
        ),
        env,
        st
      )

      ok(:map, Map.put(env, state_var, maty_actor_state_type), st)
    end
  end

  # --- IO ---
  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [IO, _]}, _, _} = ast) do
    TC.IO.tc_expr(ctx, var_env, st_pre, ast)
  end

  # --- :timer ---
  deftc tc_expr(ctx, var_env, st_pre, {{:., _, [:timer, _]}, _, _} = ast) do
    TC.Timer.tc_expr(ctx, var_env, st_pre, ast)
  end

  # --- Maty Suspend Operation (T-Suspend) ---
  # Matches throw({:suspend, handler, state}) from Maty.DSL.suspend/2
  deftc tc_expr(
          ctx,
          var_env,
          st_pre,
          {{:., _, [:erlang, :throw]}, _,
           [{:{}, meta, [:suspend, handler_ast, {state_var, _, _} = state_ast]}]}
        ) do
    # todo: threading of environment and st in with clause
    with {:h, {:ok, handler_type, h_st, h_env}} <-
           {:h, tc_expr(ctx, var_env, st_pre, handler_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(st_pre, h_st, meta),
         # pin - maybe helper could return more standard type
         {:suspension, :ok, [got: _], _st} <-
           {:suspension, Helpers.check_handler_type(handler_type, meta), [got: handler_ast],
            st_pre},
         #
         {:v, {:ok, state_type, v_st, v_env}} <- {:v, tc_expr(ctx, h_env, h_st, state_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(h_st, v_st, meta),
         {:ok, _state_type} <- Helpers.check_maty_state_type(state_type),
         {:st, %ST.SName{handler: expected_handler}, _state_var} <- {:st, v_st, state_var},
         {:handler_name, [got: ^expected_handler, expected: _expected_handler], _st} <-
           {:handler_name, [got: handler_ast, expected: expected_handler], v_st} do
      {:ok, :no_return, {:st_bottom, :suspend}, v_env}
    else
      {:error, msg, env} ->
        {:error, msg, env}

      {:error, msg} ->
        {:error, msg, var_env}

      {:st, other_st, state_var} ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: "MatyDSL.suspend(:#{handler_ast}, #{state_var})"],
            other_st
          )

        {:error, error_msg, var_env}

      {:suspension, :error, [got: got], st} ->
        error_msg =
          Error.ProtocolViolation.suspend_invalid_handler_type(ctx.module, meta, [got: got], st)

        {:error, error_msg, var_env}

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(ctx.module, meta, error_internal)
        {:error, error_msg}

      {:handler_name, handlers, st} ->
        error_msg =
          Error.ProtocolViolation.incorrect_handler_suspension(ctx.module, meta, st, handlers)

        {:error, error_msg, var_env}
    end
  end

  # --- Maty Done Operation (T-Done) ---
  # Matches throw({:done, state}) from Maty.DSL.done/1
  # AST: {:throw, meta, [{:done, state_ast}]}

  deftc tc_expr(
          ctx,
          var_env,
          st_pre,
          {{:., _, [:erlang, :throw]}, meta, [done: {state_var, _, _} = state_ast]}
        ) do
    with {:ok, state_type, v_st, v_env} <- tc_expr(ctx, var_env, st_pre, state_ast),
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(st_pre, v_st, meta),
         {:ok, _state_type} <- Helpers.check_maty_state_type(state_type),
         {:st, %ST.SEnd{}, _state_var} <- {:st, v_st, state_var} do
      {:ok, :no_return, {:st_bottom, :done}, v_env}
    else
      {:error, msg, env} ->
        {:error, msg, env}

      {:error, msg} ->
        {:error, msg, var_env}

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(ctx.module, meta, error_internal)
        {:error, error_msg}

      {:st, other_st, state_var} ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            ctx.module,
            meta,
            [got: "MatyDSL.done(#{state_var})"],
            other_st
          )

        {:error, error_msg, var_env}
    end
  end

  # --- Maty Register Operation (T-Register) V2 ---
  deftc tc_expr(
          ctx,
          var_env,
          st_pre,
          {{:., _m1, [Maty.DSL, :register]}, meta,
           [ap_pid_ast, role_ast, reg_info_ast, state_ast]}
        ) do
    with :ok,
         # is ap_pid_ast a PID?
         {:ap, {:ok, :pid, ^st_pre, _}} <- {:ap, tc_expr(ctx, var_env, st_pre, ap_pid_ast)},

         # is role_ast a role?
         {:role, {:ok, :atom, ^st_pre, _}} <-
           {:role, tc_expr(ctx, var_env, st_pre, role_ast)},

         # is init_handler a proper handler?
         # have they provided the required args?
         {:handler, {:ok, {:fun, _arity}, st_pre, var_env}} <-
           {:handler, tc_expr(ctx, var_env, st_pre, reg_info_ast)},

         # is state_ast an ActorState
         {:state, {:ok, state_type, ^st_pre, _}} <-
           {:state, tc_expr(ctx, var_env, st_pre, state_ast)},
         {:ok, _state_type} <- Helpers.check_maty_state_type(state_type),
         return_type = {:tuple, [:ok, Type.maty_actor_state()]} do
      # all checks passed

      {:ok, return_type, st_pre, var_env}
    else
      {:ap, {:error, _msg, _var_env} = error} ->
        error

      {:role, {:error, _msg, _var_env} = error} ->
        error

      {:handler, {:error, _msg, _var_env} = error} ->
        error

      {:state, {:error, _msg, _var_env} = error} ->
        error

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(ctx.module, meta, error_internal)
        {:error, error_msg}

      other ->
        # pin - convert to new kind of error
        {:error, Error.internal_error("Unexpected mismatch in register check: #{inspect(other)}"),
         var_env}
    end
  end

  # --- Function Application (T-App) ---
  # Handles local function calls: f(arg1, arg2, ...)
  deftc tc_expr(ctx, var_env, st_pre, {func_name, meta, arg_asts} = ast)
        when is_atom(func_name) and is_list(arg_asts) and meta != [] and
               func_name not in [:=, :%, :{}, :|, :<<>>] do
    arity = length(arg_asts)
    func_id = {func_name, arity}

    # todo: maybe make use of more helpers?
    # get all the type signatures
    with {:ok, signatures} when is_list(signatures) and signatures != [] <-
           Map.fetch(ctx.psi, func_id) do
      # go through each list of arguments
      Enum.reduce_while(
        arg_asts,
        {:ok, [], st_pre, var_env},
        fn arg_ast, {:ok, acc_arg_types, current_st, current_env} ->
          case tc_expr(ctx, current_env, current_st, arg_ast) do
            {:ok, actual_type, next_st, next_env} ->
              # Accumulate actual types and pass state/env forward
              # session type should remain unchanged from typechecking the individual arguments
              # but we thread it through anyway
              {:cont, {:ok, [actual_type | acc_arg_types], next_st, next_env}}

            {:error, error, err_env} ->
              # Halt on first argument error
              {:halt, {:error, error, err_env}}
          end
        end
      )
      # if we make it here it means we were able to typecheck all asts
      |> case do
        {:ok, actual_arg_types_rev, final_st, final_env} ->
          actual_arg_types = Enum.reverse(actual_arg_types_rev)

          # match on the first matching signature
          Enum.find(signatures, fn {param_types, _return_type} ->
            # Check type compatibility for this signature
            compatible? =
              actual_arg_types
              |> Enum.zip(param_types)
              |> Enum.all?(fn {got, expected} -> got == expected end)

            # Check arity
            compatible? and length(actual_arg_types) == length(param_types)
          end)
          |> case do
            {_param_types, return_type} ->
              # match exists
              {:ok, return_type, final_st, final_env}

            nil ->
              # match does not exist
              Logger.error(inspect(ast))

              error =
                Error.FunctionCall.no_matching_function_clause(
                  ctx.module,
                  meta,
                  func_id,
                  actual_arg_types
                )

              {:error, error, final_env}
          end

        {:error, error, final_env} ->
          # An error occurred during argument typechecking
          {:error, error, final_env}
      end
    else
      {:ok, []} ->
        error = Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)
        {:error, error, var_env}

      :error ->
        error = Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)
        {:error, error, var_env}
    end
  end

  # Variable Lookup (TV-Var adaptation)
  # Looking up a variable is pure; preserves session state.
  deftc tc_expr(_ctx, env, st, {var_name, meta, context})
        when is_atom(var_name) and (is_nil(context) or is_list(context)) do
    case Map.fetch(env, var_name) do
      {:ok, type} -> ok(type, env, st)
      # pin - convert to new kind of error
      :error -> error(Error.variable_not_exist(meta, var_name), env)
    end
  end

  # Clause for TV-MsgHandler, TV-InitHandler (Handler names as values)
  # These need access to the Delta environment. Preserves session state.
  # --- Simplified Handler Name / Atom Logic ---
  # Assumes variable shadowing doesn't occur for handler names.

  # This clause handles atoms that might be handler names.
  deftc tc_expr(ctx, env, st, value)
        when is_atom(value) and not is_nil(value) do
    cond do
      Map.has_key?(ctx.delta_M, value) -> ok(:maty_handler_msg, env, st)
      Map.has_key?(ctx.delta_I, value) -> ok(:maty_handler_init, env, st)
      # Not a handler name, treat as a standard atom literal.
      # Fall through by calling the more general atom clause.
      true -> ok(:atom, env, st)
    end
  end

  # General Atom Literal Clause (catches atoms not matched above)
  deftc tc_expr(_ctx, env, st, value) when is_atom(value) and not is_nil(value) do
    ok(:atom, env, st)
  end

  @doc """
  Checks if a function definition is well-formed according to WF-Func.
  Verifies argument patterns, body type, return type, and session state purity.

  Returns `{:ok, return_type}` or `{:error, message}` for each function clause checked.
  """
  @spec check_wf_function(
          ctx :: Ctx.t(),
          func_id :: {atom(), non_neg_integer()},
          clauses :: [Macro.t()]
        ) ::
          [{:ok, Type.t()} | {:error, binary()}]
  def check_wf_function(ctx, {_name, arity} = func_id, clauses) do
    case Map.fetch(ctx.psi, func_id) do
      {:ok, signatures} when is_list(signatures) ->
        defs = Enum.zip(signatures, clauses)

        for {{spec_args_types, spec_return_type},
             {clause_meta, arg_pattern_asts, _guards, body_block}} <- defs do
          with :arity_ok <-
                 Helpers.check_clause_arity(ctx, clause_meta, func_id, arity, spec_args_types),
               # pin - maybe helper could return more standard type
               {:args_ok, body_var_env} <-
                 Helpers.check_argument_patterns(
                   ctx,
                   clause_meta,
                   arg_pattern_asts,
                   spec_args_types
                 ),
               # pin - maybe helper could return more standard type
               {:body_ok, actual_return_type, final_st, _final_env} <-
                 check_function_body(ctx, body_var_env, body_block),
               # pin - maybe helper could return more standard type
               :state_ok <-
                 Helpers.check_final_session_state(ctx, clause_meta, func_id, final_st),
               :type_ok <-
                 Helpers.check_return_type(
                   ctx,
                   clause_meta,
                   actual_return_type,
                   spec_return_type
                 ) do
            {:ok, actual_return_type}
          else
            {:error, error_msg} -> {:error, error_msg}
          end
        end

      :error ->
        error = Error.TypeSpecification.no_spec_for_function(ctx.module, func_id)
        List.duplicate({:error, error}, length(clauses))
    end
  end

  @doc """
  Checks a single message handler clause based on WF-MsgHandler.

  Verifies the declared role/label/payload pattern against the session type
  associated with the handler_label, and checks if the body correctly
  implements the session continuation, ending in done/suspend.

  Returns `{:ok, {label, role}}` if well-formed, identifying the session
  branch handled. Otherwise returns `{:error, message}`.
  """
  @spec check_wf_message_handler_clause(
          ctx :: Ctx.t(),
          handler_label :: atom(),
          handler_ast_clause :: Macro.t(),
          st_pre :: ST.t(),
          type_signature :: tuple()
        ) :: {:ok, ST.SBranch.t()} | {:error, binary()}
  def check_wf_message_handler_clause(
        ctx,
        handler_label,
        {clause_meta, args, _guards, body_block},
        st_pre,
        type_signature
      ) do
    with [received_role, message_pattern_ast, state_var_ast, _session_ctx_var_ast] <- args,
         {[declared_role, message_type, _state, _session_ctx], _return_type} <- type_signature,

         # get name of state variable
         {state_var, _, _} <- state_var_ast,

         # role should already just be an atom
         {:ok, :atom, ^st_pre, _} <- tc_expr(ctx, %{}, st_pre, received_role),

         # get shape of message
         # bind whatever from the message payload
         {:ok, _message_bindings, var_env} <-
           tc_pattern(ctx, message_pattern_ast, message_type, %{}),

         # create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         # need to also add psi here
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         #  var_env = Map.merge(gamma_args_env, psi),
         # check the session type is SIn
         {:st, st = %ST.SIn{from: expected_role, branches: branches}} <- {:st, st_pre},

         # check handler and session type roles align
         {:role, [got: ^expected_role, expected: _expected_role], _st} <-
           {:role, [got: ^received_role = declared_role, expected: expected_role], st},
         {label, _} <- message_pattern_ast,
         {:tuple, [_, payload_type]} <- message_type,

         # check there is a matching branch
         # take note of this branch
         {:branch, {:ok, handler_branch}, [got: _attempted_match, expected: _branches], _st} <-
           {:branch,
            Helpers.find_matching_branch(
              branches,
              {label, payload_type}
            ), [got: {label, payload_type}, expected: branches], st},

         # extract only the relevant bits (leave out the try catch)
         body = extract_body(body_block),
         {:ok, :no_return, {:st_bottom, _exit_status}, _var_env} <-
           tc_expr_list(ctx, var_env, handler_branch.continue_as, body) do
      # all checks passed!
      {:ok, handler_branch}
    else
      {:error, msg, _env} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}

      {:st, other_st} ->
        {:error, "st broken: #{inspect(other_st)}"}

      {:role, [got: role_received, expected: role_expected], st} ->
        error_msg =
          Error.ProtocolViolation.incorrect_recipient_participant(
            ctx.module,
            handler_label,
            st,
            got: role_received,
            expected: role_expected
          )

        {:error, error_msg}

      {:branch, {:error, :label_mismatch},
       [got: {label_received, _payload_received}, expected: branches], st} ->
        branch_options = branches |> Enum.map(fn b -> b.label end)

        error_msg =
          Error.ProtocolViolation.incorrect_incoming_message_label(ctx.module, handler_label, st,
            got: label_received,
            expected: branch_options
          )

        {:error, error_msg}

      # todo: fix the double incorrect message label check
      {:branch, {:error, :payload_mismatch},
       [got: {label_received, payload_received}, expected: branches], st} ->
        expected_branch =
          branches
          |> Enum.find(fn b -> b.label == label_received end)

        case expected_branch do
          nil ->
            branch_options = branches |> Enum.map(fn b -> b.label end)

            error_msg =
              Error.ProtocolViolation.incorrect_incoming_message_label(
                ctx.module,
                handler_label,
                st,
                got: label_received,
                expected: branch_options
              )

            {:error, error_msg}

          other ->
            error_msg =
              Error.ProtocolViolation.incorrect_incoming_payload_type(
                ctx.module,
                handler_label,
                st,
                got: payload_received,
                expected: other.payload
              )

            {:error, error_msg}
        end

      {:body_ok, {final_type, final_state}, _env} ->
        error =
          Error.handler_body_wrong_termination(
            clause_meta,
            handler_label,
            final_type,
            final_state
          )

        {:error, error}

      other ->
        # pin - convert to new kind of error
        {:error, Error.internal_error("Unexpected mismatch in handler check: #{inspect(other)}")}
    end
  end

  @doc """
  Checks a single initialisation handler clause based on WF-InitHandler.

  Verifies the declared argument pattern against the spec type, and checks
  if the body correctly implements the initial session state, ending in
  done/suspend.

  Returns `{:ok, handler_label}` if well-formed. Otherwise returns `{:error, message}`.
  """

  # [
  #   {_meta, [args_ast, state_var_ast, session_ctx], [],
  #    {:try, _, [[do: {:__block__, _, [_, _, {:__block__, _, block}]}, catch: _]]}}
  # ]

  @spec check_wf_init_handler_clause(
          ctx :: Ctx.t(),
          handler_label :: atom(),
          handler_ast_clause :: Macro.t(),
          st_pre :: ST.t(),
          type_signature :: tuple()
        ) ::
          :ok | {:error, binary()}
  def check_wf_init_handler_clause(
        ctx,
        handler_label,
        {clause_meta, [arg_pattern_ast, {state_var, _, _}, _session_ctx_var_ast], _guards,
         body_block},
        st_pre,
        {[args_types, _state, _session_ctx], _return_type}
      ) do
    with {:ok, _message_bindings, var_env} <- tc_pattern(ctx, arg_pattern_ast, args_types, %{}),

         #  create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         # check the session type is NOT SIn (should be SOut or Suspend)
         {:st, :ok} <- {:st, Helpers.check_init_st(st_pre)},

         # extract only the relevant bits (leave out the try catch)
         body = extract_body(body_block),
         {:ok, :no_return, {:st_bottom, _exit_status}, _var_env} <-
           tc_expr_list(ctx, var_env, st_pre, body) do
      # all checks passed!
      :ok
    else
      {:error, msg, _env} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}

      {:body_ok, {final_type, final_state}, _env} ->
        error =
          Error.handler_body_wrong_termination(
            clause_meta,
            handler_label,
            final_type,
            final_state
          )

        {:error, error}

      {:st, {:error, _msg} = error} ->
        error

      other ->
        # pin - convert to new kind of error
        error_msg =
          Error.internal_error("Unexpected mismatch in init handler check: #{inspect(other)}")

        {:error, error_msg}
    end
  end

  def check_wf_on_link_callback(
        ctx,
        {_clause_meta, args, _guards, body_block},
        type_signature
      ) do
    with [arg_pattern_ast, state_var_ast] <- args,
         {[args_types, _state], _return_type} <- type_signature,

         #  get name of state variable
         {state_var, _, _} <- state_var_ast,

         # bind variables from the function signature
         {:ok, _message_bindings, var_env} <-
           tc_pattern(ctx, arg_pattern_ast, args_types, %{}),
         #  create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         # typecheck the function (calls to register etc.)
         body = extract_body(body_block),
         {:ok, return_type, %ST.SEnd{}, _var_env} <-
           tc_expr_list(ctx, var_env, %ST.SEnd{}, body),

         # make sure there is at least one call to register in this function
         {:register, true} <- {:register, Helpers.contains_register_call?(body)},

         # make sure the function returns {:ok, some_actor_state}
         true <- return_type == {:tuple, [:ok, Type.maty_actor_state()]} do
      # all checks pass
      :ok
    else
      {:error, msg, _var_env} -> {:error, msg}
      # pin - convert to new kind of error
      other -> {:error, "Something is not looking right: #{inspect(other)}"}
    end
  end

  # move
  # Processes a list of expressions sequentially using tc_expr.
  # Returns the result of the *last* expression in the list.
  @spec tc_expr_list(
          ctx :: Ctx.t(),
          var_env :: var_env(),
          st_pre :: ST.t(),
          ast_list :: [ast()]
        ) ::
          result()
  def tc_expr_list(_ctx, env, st, []) do
    # Result of an empty block is nil, state preserved.
    ok(nil, env, st)
  end

  def tc_expr_list(ctx, var_env, st_pre, ast_list) do
    traverse(ast_list, var_env, st_pre, fn ast, env, st -> tc_expr(ctx, env, st, ast) end)
    |> map(&List.last/1)
  end

  # move
  # check if argument alters session state
  defp check_function_body(ctx, body_var_env, body_block) do
    body_asts = extract_body(body_block)
    initial_st = %ST.SEnd{}

    case tc_expr_list(ctx, body_var_env, initial_st, body_asts) do
      {:ok, return_type, final_st, final_env} ->
        {:body_ok, return_type, final_st, final_env}

      {:error, msg, _env} ->
        {:error, msg}
    end
  end

  # move ?
  # Extracts a list of expressions from an AST body.
  #
  # This handles both block expressions (`do: begin ... end`) and single expressions.
  #
  # Returns:
  #   - A list of expressions representing the body
  @spec extract_body(Macro.t()) :: [Macro.t()]

  defp extract_body({:__block__, _, block}), do: block

  defp extract_body({:try, _, [[do: {:__block__, _, [_, _, body_block]}, catch: _]]}),
    do: extract_body(body_block)

  defp extract_body(expr) when not is_list(expr), do: [expr]

  # --- even more private helpers

  defp guard_atom(type, meta, ctx, env, st) do
    lift_bool(
      type == :atom,
      Error.PatternMatching.invalid_map_key_type(ctx.module, meta,
        expected: :atom,
        got: type
      ),
      env,
      st
    )
  end

  defp lift_literal(key_ast, meta, ctx, env, st) do
    lift_result(
      Helpers.ast_to_literal(key_ast),
      Error.PatternMatching.complex_map_key(ctx.module, meta, key_ast),
      env,
      st
    )
  end

  defp lift_pattern(ctx, pattern_ast, scrutinee_type, env, st) do
    case tc_pattern(ctx, pattern_ast, scrutinee_type, env) do
      {:ok, _bindings, new_env} -> ok(nil, new_env, st)
      {:error, msg, err_env} -> error(msg, err_env)
    end
  end
end
