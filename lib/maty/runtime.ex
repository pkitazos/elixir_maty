defmodule Maty.Runtime do
  alias Maty.Types
  alias Maty.Runtime.{Envelope, InternalState, Session}

  require Logger

  @moduledoc """
  Runtime internals
  """

  @doc false
  @spec init_and_run(module(), any()) :: no_return()
  def init_and_run(module, args) do
    {:ok, global_s} = module.on_start(args)

    loop(module, InternalState.new(global_s), [])
  end

  @spec loop(module(), InternalState.t(), list(Envelope.t())) :: no_return()
  defp loop(module, s, stash) do
    traverse_stash(module, s, stash, [])
  end

  # Since processing a message progresses the session (via suspend or done)
  # we must then loop back to the start of the stash as messages which previously were unprocessable, may now be processable.
  # This is the common case: a message is stashed because its sender wasn't expected yet and becomes processable once the session moves on.
  @spec traverse_stash(module(), InternalState.t(), list(Envelope.t()), list(Envelope.t())) ::
          no_return()
  defp traverse_stash(module, s, [envelope | rest], skipped) do
    if can_process?(s, envelope) do
      updated_s = process_message(module, s, envelope)
      loop(module, updated_s, skipped ++ rest)
    else
      traverse_stash(module, s, rest, skipped ++ [envelope])
    end
  end

  defp traverse_stash(module, s, [], stash) do
    # in this clause we've checked every message in the stash and no handler can process any of them
    # so we take the first message in our mailbox
    receive_next(module, s, stash)
  end

  # If we traverse the entire stash and find no message that any of our currently suspended handlers can process
  # we move on to processing messages from our mailbox. A similar process is done here.
  # We inspect which session and to which role this message was addressed and check whether the suspended handler can process this message.
  # If it can, we process the message and loop back to the start, otherwise we stash this message and then loop back to the start.
  @spec receive_next(module(), InternalState.t(), list(Envelope.t())) :: no_return()
  defp receive_next(module, s, stash) do
    receive do
      {:maty_message, %Envelope{} = envelope} ->
        if can_process?(s, envelope) do
          updated_s = process_message(module, s, envelope)
          loop(module, updated_s, stash)
        else
          loop(module, s, stash ++ [envelope])
        end

      {:init_session, session_id, participants, init_token} ->
        updated_s = init_role(module, s, session_id, participants, init_token)
        loop(module, updated_s, stash)

      other ->
        Logger.warning("[#{inspect(module)}] discarding unexpected message: #{inspect(other)}")
        loop(module, s, stash)
    end
  end

  @spec process_message(module(), InternalState.t(), Envelope.t()) :: InternalState.t()
  defp process_message(module, s, %Envelope{
         session_id: session_id,
         to: to,
         from: from,
         message: msg
       }) do
    session = s.sessions[session_id]
    {handler_label, _} = session.roles[to].handler

    result =
      apply(module, handler_label, [
        from,
        msg,
        InternalState.get_actor_state(s, session_id, to),
        {session, to}
      ])

    handle_result(module, s, result, session_id, to)
  end

  @spec init_role(
          module(),
          InternalState.t(),
          Types.session_id(),
          %{Types.role() => pid()},
          Types.init_token()
        ) :: InternalState.t()
  defp init_role(module, s, session_id, participants, init_token) do
    # take the `role` and `callback` for the given `init_token`
    {{role, init_handler, args}, initial_s} = pop_in(s.callbacks[init_token])

    # it's possible that at this stage the actor has already initiated the session with a different role
    # or maybe not, so we must ensure that a session exists
    updated_s = ensure_session(initial_s, session_id, participants)
    session = updated_s.sessions[session_id]

    result =
      apply(module, init_handler, [
        args,
        InternalState.get_actor_state(updated_s, session_id, role),
        {session, role}
      ])

    handle_result(module, updated_s, result, session_id, role)
  end

  @spec handle_result(
          module(),
          InternalState.t(),
          {:suspend, Types.handler_label(), term()} | {:done, term()},
          #                                   ^ gotta somehow type this
          Types.session_id(),
          Types.role()
        ) :: InternalState.t()

  defp handle_result(
         module,
         s,
         {:suspend, next_handler, actor_state},
         session_id,
         role
       ) do
    expected = module.__handler_expects__(next_handler)

    s =
      put_in(
        s.sessions[session_id].roles[role],
        %{handler: {next_handler, expected}, state: actor_state.local}
      )

    %{s | global_actor_state: actor_state.global}
  end

  defp handle_result(_module, s, {:done, actor_state}, session_id, role) do
    remaining = Map.delete(s.sessions[session_id].roles, role)

    s =
      if remaining == %{} do
        update_in(s.sessions, &Map.delete(&1, session_id))
      else
        put_in(s.sessions[session_id].roles, remaining)
      end

    %{s | global_actor_state: actor_state.global}
  end

  @spec can_process?(InternalState.t(), Envelope.t()) :: boolean()
  defp can_process?(s, envelope) do
    with {:ok, session} <- Map.fetch(s.sessions, envelope.session_id),
         {:ok, %{handler: {_, expected_role}}} <- Map.fetch(session.roles, envelope.to) do
      expected_role == envelope.from
    else
      :error -> false
    end
  end

  @spec ensure_session(InternalState.t(), Types.session_id(), %{Types.role() => pid()}) ::
          InternalState.t()
  defp ensure_session(s, session_id, participants) do
    %{
      s
      | sessions: Map.put_new(s.sessions, session_id, Session.new(session_id, participants))
    }
  end
end
