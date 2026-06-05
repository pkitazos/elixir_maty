defmodule Maty.Typechecker.TC.WF do
  @moduledoc """
  Well-formedness checks for function definitions and handler clauses.

  Implements the formal rules WF-Func, WF-MsgHandler, WF-InitHandler,
  and WF-OnLink, checking that definitions conform to their declared
  type specifications and session type annotations.
  """

  alias Maty.ST
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{TC, Error, Ctx, Helpers}

  import Maty.Typechecker.PatternBinding, only: [tc_pattern: 4]

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
        with :ok <- check_clause_arity(ctx, meta, func_id, arity, spec_args),
             {:ok, env} <-
               check_argument_patterns(
                 ctx,
                 meta,
                 arg_pattern_asts,
                 spec_args
               ),
             {:ok, {return_type, st}} <- check_function_body(ctx, env, body_block),
             :ok <- check_final_session_state(ctx, meta, func_id, st),
             :ok <-
               check_return_type(
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
         {:ok, :atom, ^st_pre, env} <- TC.tc_expr(ctx, %{}, st_pre, received_role),
         # bind variables from the message pattern
         {:ok, _bindings, env} <- tc_pattern(ctx, message_pattern_ast, message_type, env),
         # extend env with state variable binding
         env = Map.put(env, state_var, Type.maty_actor_state()),
         # typecheck the handler body
         {:ok, return_type, final_st, _} <-
           TC.tc_expr_list(ctx, env, handler_branch.continue_as, extract_body(body_block)),
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
         :ok <- check_init_st(st_pre),
         # typecheck the handler body
         {:ok, return_type, st, _} <-
           TC.tc_expr_list(ctx, env, st_pre, extract_body(body_block)),
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
         {:ok, return_type, final_st, _env} <- TC.tc_expr_list(ctx, env, %ST.SEnd{}, body),
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

  # --- Private helpers ---

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

  defp check_function_body(ctx, body_var_env, body_block) do
    body_asts = extract_body(body_block)
    initial_st = %ST.SEnd{}

    case TC.tc_expr_list(ctx, body_var_env, initial_st, body_asts) do
      {:ok, return_type, final_st, _final_env} -> {:ok, {return_type, final_st}}
      {:error, msg, _env} -> {:error, msg}
    end
  end

  @spec extract_body(Macro.t()) :: [Macro.t()]

  defp extract_body({:__block__, _, block}), do: block

  defp extract_body({:try, _, [[do: {:__block__, _, [_, _, body_block]}, catch: _]]}),
    do: extract_body(body_block)

  defp extract_body(expr) when not is_list(expr), do: [expr]

  # --- Private helpers (from helpers.ex) ---

  # pin - convert to new kind of error
  defp check_init_st(%ST.SIn{}), do: {:error, "Session precondition cannot be a receive"}
  defp check_init_st(_st), do: :ok

  defp check_clause_arity(ctx, meta, func_id, arity, spec_args_types) do
    if arity == length(spec_args_types) do
      :ok
    else
      {:error,
       Error.FunctionCall.arity_mismatch(ctx.module, meta, func_id,
         expected: length(spec_args_types),
         got: arity
       )}
    end
  end

  defp check_final_session_state(_ctx, _meta, _func_id, %ST.SEnd{}), do: :ok

  defp check_final_session_state(ctx, meta, func_id, other_st) do
    error = Error.FunctionCall.function_altered_session_state(ctx.module, meta, func_id, other_st)
    {:error, error}
  end

  defp check_return_type(ctx, meta, actual_return_type, spec_return_type) do
    if actual_return_type == spec_return_type do
      :ok
    else
      {:error,
       Error.TypeMismatch.return_type_mismatch(ctx.module, meta,
         expected: spec_return_type,
         got: actual_return_type
       )}
    end
  end

  defp check_argument_patterns(ctx, meta, arg_pattern_asts, spec_args_types) do
    initial_arg_env = %{}

    Enum.zip(arg_pattern_asts, spec_args_types)
    |> Enum.reduce_while(
      {:ok, %{}, initial_arg_env},
      fn {p_ast, expected_type}, {:ok, acc_bindings, current_env} ->
        with {:ok, new_bindings, updated_env} <-
               tc_pattern(ctx, p_ast, expected_type, current_env),
             {:ok, merged_bindings, _env_ignored} <-
               Helpers.check_and_merge_bindings(
                 ctx.module,
                 meta,
                 acc_bindings,
                 new_bindings,
                 current_env
               ) do
          {:cont, {:ok, merged_bindings, updated_env}}
        else
          {:error, msg, _env} -> {:halt, {:error, msg}}
        end
      end
    )
    |> case do
      {:ok, _final_bindings, body_var_env} -> {:ok, body_var_env}
      {:error, msg} -> {:error, msg}
    end
  end
end
