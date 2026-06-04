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
    items
    |> traverse(env, st, fn item, env, st -> tc_expr(ctx, env, st, item) end)
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
    items
    |> traverse(var_env, st_pre, fn item, env, st -> tc_expr(ctx, env, st, item) end)
    |> map(fn types -> {:tuple, types} end)
  end

  # Map Construction %{k1 => v1, ...} (Val-Map / Val-EmptyMap adaptation)
  # Allows heterogeneous value types, deviates slightly from our formalisation
  deftc tc_expr(_ctx, env, st, {:%{}, _, []}) do
    ok({:map, %{}}, env, st)
  end

  # Clause for Non-Empty Map %{k1 => v1, ...}
  deftc tc_expr(ctx, env, st, {:%{}, meta, pairs}) when is_list(pairs) do
    pairs
    |> traverse(env, st, fn {key_ast, val_ast}, env, st ->
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
    tc_expr(ctx, env, st, scrutinee_ast)
    |> bind(fn scrutinee_type, env, st ->
      st_pre = st

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
          env,
          %ST.SOut{to: expected_role, branches: branches} = st,
          {{:., meta, [Maty.DSL, :internal_send]}, _, [_session_ctx, recipient_ast, message_ast]}
        ) do
    thread do
      _recipient_type
      <~ (
        st_pre = st
        tc_expr(ctx, env, st, recipient_ast)
      )

      # Ensure recipient check pure
      :ok <~ Helpers.check_st_unchanged(st_pre, st, meta)

      # Check recipient matches expected role
      _
      <~ lift_bool(
        recipient_ast == expected_role,
        Error.ProtocolViolation.incorrect_target_participant(
          ctx.module,
          meta,
          st_pre,
          got: recipient_ast,
          expected: expected_role
        ),
        env,
        st
      )

      # Check message structure {label, payload_expr}
      {literal_label, payload_expr_ast}
      <~ lift_result(Helpers.check_message_structure(ctx, meta, message_ast), env, st)

      # Typecheck payload expression
      actual_payload_type <~ tc_expr(ctx, env, st, payload_expr_ast)
      # Ensure payload check pure
      :ok <~ Helpers.check_st_unchanged(st_pre, st, meta)

      # Find matching branch for the label
      matched_branch
      <~ case Helpers.find_matching_branch(branches, {literal_label, actual_payload_type}) do
        {:ok, branch} ->
          ok(branch, env, st)

        {:error, :label_mismatch} ->
          branch_options = Enum.map(branches, fn b -> b.label end)

          error(
            Error.ProtocolViolation.incorrect_message_label(
              ctx.module,
              meta,
              st_pre,
              got: literal_label,
              expected: branch_options
            ),
            env
          )

        {:error, :payload_mismatch} ->
          case Enum.find(branches, fn b -> b.label == literal_label end) do
            nil ->
              branch_options = Enum.map(branches, fn b -> b.label end)

              error(
                Error.ProtocolViolation.incorrect_message_label(
                  ctx.module,
                  meta,
                  st_pre,
                  got: literal_label,
                  expected: branch_options
                ),
                env
              )

            other ->
              error(
                Error.ProtocolViolation.incorrect_payload_type(
                  ctx.module,
                  meta,
                  st_pre,
                  got: actual_payload_type,
                  expected: other.payload
                ),
                env
              )
          end
      end

      # Check payload type matches expected
      _
      <~ lift_bool(
        actual_payload_type == matched_branch.payload,
        Error.ProtocolViolation.incorrect_payload_type(
          ctx.module,
          meta,
          st_pre,
          got: actual_payload_type,
          expected: matched_branch.payload
        ),
        env,
        st
      )

      (
        # to silence macro warning
        _ = st
        ok(:atom, env, matched_branch.continue_as)
      )
    end
  end

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., meta, [Maty.DSL, :internal_send]}, _, [_session_ctx, recipient_ast, _message_ast]}
        ) do
    error(
      Error.ProtocolViolation.incorrect_action(
        ctx.module,
        meta,
        # todo: try to render shape of message
        [got: "MatyDSL.send(:#{recipient_ast}, message)"],
        st
      ),
      env
    )
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
          env,
          st,
          {{:., _, [:erlang, :throw]}, _,
           [{:{}, meta, [:suspend, handler_ast, {state_var, _, _} = state_ast]}]}
        ) do
    thread do
      handler_type
      <~ (
        st_pre = st
        tc_expr(ctx, env, st, handler_ast)
      )

      :ok <~ Helpers.check_st_unchanged(st_pre, st, meta)

      _
      <~ case Helpers.check_handler_type(handler_type) do
        :ok ->
          ok(nil, env, st)

        {:error, :not_a_handler} ->
          error(
            Error.ProtocolViolation.suspend_invalid_handler_type(
              ctx.module,
              meta,
              [got: handler_ast],
              st
            ),
            env
          )
      end

      state_type
      <~ (
        st_pre = st
        tc_expr(ctx, env, st, state_ast)
      )

      :ok <~ Helpers.check_st_unchanged(st_pre, st, meta)

      _
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

      expected_handler
      <~ case st do
        %ST.SName{handler: expected_handler} ->
          ok(expected_handler, env, st)

        other_st ->
          error(
            Error.ProtocolViolation.incorrect_action(
              ctx.module,
              meta,
              [got: "MatyDSL.suspend(:#{handler_ast}, #{state_var})"],
              other_st
            ),
            env
          )
      end

      _
      <~ lift_bool(
        expected_handler == handler_ast,
        Error.ProtocolViolation.incorrect_handler_suspension(
          ctx.module,
          meta,
          st,
          got: handler_ast,
          expected: expected_handler
        ),
        env,
        st
      )

      (
        _ = st
        ok(:no_return, env, {:st_bottom, :suspend})
      )
    end
  end

  # --- Maty Done Operation (T-Done) ---
  # Matches throw({:done, state}) from Maty.DSL.done/1
  # AST: {:throw, meta, [{:done, state_ast}]}

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _, [:erlang, :throw]}, meta, [done: {state_var, _, _} = state_ast]}
        ) do
    thread do
      state_type
      <~ (
        st_pre = st
        tc_expr(ctx, env, st, state_ast)
      )

      :ok <~ Helpers.check_st_unchanged(st_pre, st, meta)

      _
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

      _
      <~ case st do
        %ST.SEnd{} ->
          ok(nil, env, st)

        other_st ->
          error(
            Error.ProtocolViolation.incorrect_action(
              ctx.module,
              meta,
              [got: "MatyDSL.done(#{state_var})"],
              other_st
            ),
            env
          )
      end

      (
        _ = st
        ok(:no_return, env, {:st_bottom, :done})
      )
    end
  end

  # --- Maty Register Operation (T-Register) V2 ---
  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _m1, [Maty.DSL, :register]}, meta,
           [ap_pid_ast, role_ast, reg_info_ast, state_ast]}
        ) do
    thread do
      pid_type <~ tc_expr(ctx, env, st, ap_pid_ast)
      # todo: better error
      _ <~ lift_bool(pid_type == :pid, "AP must be a PID", env, st)
      # todo: also check session type is not progressing

      role_type <~ tc_expr(ctx, env, st, role_ast)
      # todo: better error
      _ <~ lift_bool(role_type == :atom, "role must be a atom", env, st)
      # todo: also check session type is not progressing

      init_handler_type <~ tc_expr(ctx, env, st, reg_info_ast)
      # todo: better error
      _ <~ lift_bool(match?({:fun, _}, init_handler_type), "handler must be a function", env, st)
      # todo: also check session type is not progressing

      state_type <~ tc_expr(ctx, env, st, state_ast)
      # todo: fix error
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

      # todo: also check session type is not progressing

      ok({:tuple, [:ok, maty_actor_state_type]}, env, st)
    end
  end

  # --- Function Application (T-App) ---
  # Handles local function calls: f(arg1, arg2, ...)
  deftc tc_expr(ctx, env, st, {func_name, meta, arg_asts})
        when is_atom(func_name) and is_list(arg_asts) and meta != [] and
               func_name not in [:=, :%, :{}, :|, :<<>>] do
    func_id = {func_name, length(arg_asts)}

    with {:ok, signatures} when is_list(signatures) and signatures != [] <-
           Map.fetch(ctx.psi, func_id) do
      arg_asts
      |> traverse(env, st, fn arg_ast, env, st -> tc_expr(ctx, env, st, arg_ast) end)
      |> bind(fn arg_types, env, st ->
        case Enum.find(signatures, fn {param_types, _return_type} -> arg_types == param_types end) do
          {_param_types, return_type} ->
            ok(return_type, env, st)

          nil ->
            error(
              Error.FunctionCall.no_matching_function_clause(
                ctx.module,
                meta,
                func_id,
                arg_types
              ),
              env
            )
        end
      end)
    else
      {:ok, []} ->
        error = Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)
        {:error, error, env}

      :error ->
        error = Error.FunctionCall.function_not_exist(ctx.module, meta, func_id)
        {:error, error, env}
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
    with {:ok, signatures} when is_list(signatures) <- Map.fetch(ctx.psi, func_id) do
      for {{spec_args, spec_return}, {meta, arg_pattern_asts, _guards, body_block}} <-
            Enum.zip(signatures, clauses) do
        with :ok <- Helpers.check_clause_arity(ctx, meta, func_id, arity, spec_args),
             {:ok, env} <-
               Helpers.check_argument_patterns(
                 ctx,
                 meta,
                 arg_pattern_asts,
                 spec_args
               ),
             {:ok, {return_type, st}} <- check_function_body(ctx, env, body_block),
             :ok <- Helpers.check_final_session_state(ctx, meta, func_id, st),
             :ok <-
               Helpers.check_return_type(
                 ctx,
                 meta,
                 return_type,
                 spec_return
               ) do
          {:ok, return_type}
        else
          {:error, error_msg} -> {:error, error_msg}
        end
      end
    else
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
        {meta,
         [
           received_role,
           {label, _} = message_pattern_ast,
           {state_var, _, _},
           _session_ctx_var_ast
         ], _guards, body_block},
        st_pre,
        {[declared_role, {:tuple, [_, payload_type]} = message_type, _state, _session_ctx],
         _return_type}
      ) do
    with %ST.SIn{from: expected_role, branches: branches} <- st_pre,
         # check handler and session type roles align
         :ok <-
           check_handler_roles(
             ctx,
             handler_label,
             st_pre,
             received_role,
             declared_role,
             expected_role
           ),
         # check there is a matching branch for this label + payload
         {:ok, handler_branch} <-
           match_handler_branch(ctx, handler_label, st_pre, branches, label, payload_type),
         # typecheck received role is an atom
         {:ok, :atom, ^st_pre, env} <- tc_expr(ctx, %{}, st_pre, received_role),
         # bind variables from the message pattern
         {:ok, _bindings, env} <- tc_pattern(ctx, message_pattern_ast, message_type, env),
         # extend env with state variable binding
         env = Map.put(env, state_var, Type.maty_actor_state()),
         # typecheck the handler body
         {:ok, return_type, final_st, _} <-
           tc_expr_list(ctx, env, handler_branch.continue_as, extract_body(body_block)),
         # body must terminate with :no_return and exhausted session
         :ok <- check_handler_termination(meta, handler_label, return_type, final_st) do
      {:ok, handler_branch}
    else
      {:error, msg, _env} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}

      other_st ->
        {:error, Error.internal_error("Expected SIn session type, got: #{inspect(other_st)}")}
    end
  end

  defp check_handler_roles(ctx, handler_label, st, received_role, declared_role, expected_role) do
    if received_role == expected_role and declared_role == expected_role do
      :ok
    else
      got = if received_role != expected_role, do: received_role, else: declared_role

      {:error,
       Error.ProtocolViolation.incorrect_recipient_participant(
         ctx.module,
         handler_label,
         st,
         got: got,
         expected: expected_role
       )}
    end
  end

  defp match_handler_branch(ctx, handler_label, st, branches, label, payload_type) do
    case Helpers.find_matching_branch(branches, {label, payload_type}) do
      {:ok, branch} ->
        {:ok, branch}

      {:error, :label_mismatch} ->
        {:error,
         Error.ProtocolViolation.incorrect_incoming_message_label(
           ctx.module,
           handler_label,
           st,
           got: label,
           expected: Enum.map(branches, & &1.label)
         )}

      {:error, :payload_mismatch} ->
        expected_branch = Enum.find(branches, fn b -> b.label == label end)

        if expected_branch do
          {:error,
           Error.ProtocolViolation.incorrect_incoming_payload_type(
             ctx.module,
             handler_label,
             st,
             got: payload_type,
             expected: expected_branch.payload
           )}
        else
          {:error,
           Error.ProtocolViolation.incorrect_incoming_message_label(
             ctx.module,
             handler_label,
             st,
             got: label,
             expected: Enum.map(branches, & &1.label)
           )}
        end
    end
  end

  defp check_handler_termination(_meta, _handler_label, :no_return, {:st_bottom, _}), do: :ok

  defp check_handler_termination(meta, handler_label, return_type, final_st) do
    {:error, Error.handler_body_wrong_termination(meta, handler_label, return_type, final_st)}
  end

  @doc """
  Checks a single initialisation handler clause based on WF-InitHandler.

  Verifies the declared argument pattern against the spec type, and checks
  if the body correctly implements the initial session state, ending in
  done/suspend.

  Returns `{:ok, handler_label}` if well-formed. Otherwise returns `{:error, message}`.
  """
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
        {meta, [arg_pattern_ast, {state_var, _, _}, _session_ctx_var_ast], _guards, body_block},
        st_pre,
        {[args_types, _state, _session_ctx], _return_type}
      ) do
    with nil,
         # bind variables from the argument pattern
         {:ok, _bindings, env} <- tc_pattern(ctx, arg_pattern_ast, args_types, %{}),
         # extend env with state variable binding
         env = Map.put(env, state_var, Type.maty_actor_state()),
         # session type must not be SIn (should be SOut or Suspend)
         :ok <- Helpers.check_init_st(st_pre),
         # typecheck the handler body
         {:ok, return_type, st, _} <-
           tc_expr_list(ctx, env, st_pre, extract_body(body_block)),
         # body must terminate with :no_return and exhausted session
         :ok <- check_handler_termination(meta, handler_label, return_type, st) do
      :ok
    else
      {:error, msg, _env} -> {:error, msg}
      {:error, msg} -> {:error, msg}
    end
  end

  def check_wf_on_link_callback(
        ctx,
        {_meta, [arg_pattern_ast, {state_var, _, _}], _guards, body_block},
        {[args_types, _state], _return_type}
      ) do
    body = extract_body(body_block)

    with nil,
         # bind variables from the function signature
         {:ok, _bindings, env} <- tc_pattern(ctx, arg_pattern_ast, args_types, %{}),
         # extend env with state variable binding
         env = Map.put(env, state_var, Type.maty_actor_state()),
         # typecheck the body (calls to register etc.)
         {:ok, return_type, final_st, _env} <- tc_expr_list(ctx, env, %ST.SEnd{}, body),
         # session state must not change
         :ok <- check_on_link_session_state(final_st),
         # must contain at least one call to Maty.DSL.register
         :ok <- check_contains_register(body),
         # must return {:ok, actor_state}
         :ok <- check_on_link_return_type(return_type) do
      :ok
    else
      {:error, msg, _env} -> {:error, msg}
      {:error, msg} -> {:error, msg}
    end
  end

  defp check_on_link_session_state(%ST.SEnd{}), do: :ok

  defp check_on_link_session_state(other_st) do
    {:error, "on_link callback altered session state: #{inspect(other_st)}"}
  end

  defp check_contains_register(body) do
    if Helpers.contains_register_call?(body),
      do: :ok,
      else: {:error, "on_link callback must contain at least one call to register"}
  end

  defp check_on_link_return_type(return_type) do
    if return_type == {:tuple, [:ok, Type.maty_actor_state()]} do
      :ok
    else
      {:error, "on_link callback must return {:ok, actor_state}, got: #{inspect(return_type)}"}
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
    ast_list
    |> traverse(var_env, st_pre, fn ast, env, st -> tc_expr(ctx, env, st, ast) end)
    |> map(&List.last/1)
  end

  # move
  # check if argument alters session state
  defp check_function_body(ctx, body_var_env, body_block) do
    body_asts = extract_body(body_block)
    initial_st = %ST.SEnd{}

    case tc_expr_list(ctx, body_var_env, initial_st, body_asts) do
      {:ok, return_type, final_st, _final_env} -> {:ok, {return_type, final_st}}
      {:error, msg, _env} -> {:error, msg}
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
