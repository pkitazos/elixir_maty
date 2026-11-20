defmodule Maty.Typechecker.TC.WF do
  @moduledoc """
  Well-formedness checks for function definitions and handler clauses.

  Implements the formal rules WF-Func, WF-MsgHandler, WF-InitHandler,
  and WF-OnStart, checking that definitions conform to their declared
  type specifications and session type annotations.
  """

  alias Maty.ST.SBottom
  alias Maty.Types
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{TC, Error, Ctx, Helpers}

  import Maty.Typechecker.PatternBinding, only: [tc_pattern: 4]

  @typedoc "A function clause from debug info: {meta, args, guards, body}"
  @type clause :: {Keyword.t(), [Macro.t()], [Macro.t()], Macro.t()}

  @doc """
  Checks if a function definition is well-formed according to WF-Func.
  Verifies argument patterns, body type, return type, and session state purity.

  Returns `{:ok, return_type}` or `{:error, error}` for each function clause checked,
  or a single `{:error, error}` (not in a list) when the problem is with the function as a
  whole (no spec, or a spec count that does not fit its clauses), so it is reported once.
  """
  # todo: use `func_id()`
  @spec check_wf_function(Ctx.t(), {atom(), non_neg_integer()}, [clause()]) ::
          [{:ok, Type.t()} | {:error, Error.t()}] | {:error, Error.t()}
  def check_wf_function(ctx, {name, arity}, clauses) do
    func_id = {ctx.module, name, arity}

    with {:ok, {:function, args_ty, ret_ty}} <- Map.fetch(ctx.signatures, func_id) do
      for {meta, arg_pattern_asts, _guards, block} <- clauses do
        # errors that have no more precise location of their own are reported at this clause
        ctx = %{ctx | meta: meta}

        with {:ok, env} <- check_argument_patterns(ctx, meta, arg_pattern_asts, args_ty),
             {:ok, _, _, _} <- TC.check(ctx, env, %SBottom{reason: :nothing}, block, ret_ty) do
          {:ok, ret_ty}
        else
          {:error, error, _} -> {:error, error}
          {:error, error} -> {:error, error}
        end
      end
    else
      :error ->
        # reported at the first clause since the spec belongs to the function as a whole
        {first_clause_meta, _, _, _} = hd(clauses)

        {:error,
         Error.TypeSpecification.no_spec_for_function(ctx.module, first_clause_meta, func_id)}
    end
  end

  @doc """
  Checks a single message handler clause based on WF-MsgHandler.

  Verifies the declared role/label/payload pattern against the session type
  associated with the handler_label, and checks if the body correctly
  implements the session continuation, ending in done/suspend.

  Returns `{:ok, branch}` if well-formed, where `branch` is the session
  branch the clause handles. Otherwise returns `{:error, error}`.
  """
  @spec check_wf_message_handler_clause(Ctx.t(), Types.handler_label(), clause(), ST.SIn.t()) ::
          {:ok, ST.SBranch.t()} | {:error, Error.t()}
  def check_wf_message_handler_clause(
        ctx,
        handler,
        {meta, [role, {label, payload}, state, _session_ctx], _, block},
        %ST.SIn{} = st
      ) do
    ctx = %{ctx | meta: meta}

    with {:role, true, _} <- {:role, st.from == role, st.from},
         {:branch, %ST.SBranch{} = b} <- {:branch, Enum.find(st.branches, &(&1.label == label))},
         #
         {:ok, _bindings, env} <- tc_pattern(ctx, payload, b.payload, %{}),
         {:ok, _bindings, env} <- tc_pattern(ctx, state, ctx.handler_state_type, env),
         #
         # the body starts from the continuation of the branch this clause handles
         :ok <- typecheck_handler_body(ctx, env, meta, handler, b.continue_as, block) do
      {:ok, b}
    else
      {:role, false, from} ->
        {:error,
         Error.ProtocolViolation.incorrect_recipient_participant(
           ctx.module,
           ctx.meta,
           handler,
           st,
           received: role,
           expected: from
         )}

      {:branch, nil} ->
        {:error,
         Error.ProtocolViolation.incorrect_incoming_message_label(
           ctx.module,
           ctx.meta,
           handler,
           st,
           got: label,
           expected: Enum.map(st.branches, & &1.label)
         )}

      {:error, err, _env} ->
        {:error, err}

      {:error, err} ->
        {:error, err}
    end
  end

  @doc """
  Checks a single initialisation handler clause based on WF-InitHandler.

  Verifies the declared argument pattern against the spec type, and checks
  if the body correctly implements the initial session state, ending in
  done/suspend.

  Returns `{:ok, handler_label}` if well-formed. Otherwise returns `{:error, error}`.
  """
  @spec check_wf_init_handler_clause(
          Ctx.t(),
          Types.handler_label(),
          clause(),
          ST.t(),
          Type.t()
        ) ::
          :ok | {:error, Error.t()}
  def check_wf_init_handler_clause(ctx, handler, {meta, _, _, _}, %ST.SIn{} = st, _) do
    {:error,
     Error.ProtocolViolation.init_handler_starts_with_receive(ctx.module, meta, handler, st)}
  end

  def check_wf_init_handler_clause(
        ctx,
        handler,
        {meta, [arg_pattern_ast, state, _session_ctx], _guards, block},
        st,
        args_ty
      ) do
    ctx = %{ctx | meta: meta}

    with {:ok, _bindings, env} <- tc_pattern(ctx, arg_pattern_ast, args_ty, %{}),
         {:ok, _bindings, env} <- tc_pattern(ctx, state, ctx.handler_state_type, env),
         :ok <- typecheck_handler_body(ctx, env, meta, handler, st, block) do
      :ok
    else
      {:error, err, _env} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  def check_wf_on_start_callback(
        ctx,
        {meta, [arg_pattern_ast], _guards, block},
        {:function, [args_types], ret_ty}
      ) do
    ctx = %{ctx | meta: meta}

    with {:ok, _bindings, env} <- tc_pattern(ctx, arg_pattern_ast, args_types, %{}),
         {:ok, _, _, _} <- TC.check(ctx, env, %SBottom{reason: :nothing}, block, ret_ty),
         # todo: also check the module defines at least one init handler without one the actor can never start a session
         # (which is a bit odd for a Maty actor)
         {:register, true} <- {:register, contains_register_call?(block)} do
      :ok
    else
      {:error, err, _env} ->
        {:error, err}

      {:error, err} ->
        {:error, err}

      {:register, _} ->
        {:error, Error.FrameworkUsage.missing_session_registration(ctx.module, ctx.meta)}
    end
  end

  # -- private helpers

  # body of a handler clause must end in `suspend` / `done` with the session used up
  defp typecheck_handler_body(ctx, env, meta, handler, st, block) do
    case TC.synth(ctx, env, st, unwrap_body(block)) do
      {:ok, :no_return, %SBottom{}, _} ->
        :ok

      {:ok, ret_ty, final_st, _} ->
        {:error,
         Error.ProtocolViolation.handler_body_wrong_termination(meta, handler, ret_ty, final_st)}

      {:error, err, _env} ->
        {:error, err}
    end
  end

  defp unwrap_body({:try, _, [[do: body, catch: _]]}), do: body
  defp unwrap_body(body), do: body

  # -- privater helpers
  # todo: figure out what stays and what moves

  @spec contains_register_call?(Macro.t()) :: boolean()
  defp contains_register_call?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [Maty.Runtime, :register]}, _meta, _args} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
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
          {:error, err, _env} -> {:halt, {:error, err}}
        end
      end
    )
    |> case do
      {:ok, _final_bindings, body_var_env} -> {:ok, body_var_env}
      {:error, err} -> {:error, err}
    end
  end
end
