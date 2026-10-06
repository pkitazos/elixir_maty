defmodule Maty.Actor do
  @moduledoc """
  An actor can have multiple roles in different or even in the same session
  at any point in time an actor has suspended with a handler that is able to process the next message in the session for a given role
  that is why an actor keeps an internal state at runtime which maps session IDs to another map which maps roles to handler
  For any given session * role pair, an actor only has one valid handler and one valid continuation.

  The BEAM is not really designed with this in mind, so actors only really have a single mailbox which just interleaves all messages
  from all sessions. The runtime _does_ guarantee that messages from a given process will arrive in order in another process' mailbox
  but that's about it. The Maty runtime allows us to reorder messages in the mailbox keeping the relative order between participant messages
  the same, which essentially gives us the power to reason about our mailbox as a set of mailboxes indexed by a session

  To emulate this behaviour, a Maty actor keeps an internal stash which acts in the same way (ish).
  An actor is constantly looping over the stash and its mailbox trying to process messages.
  A message from another Maty actor always arrives as a `Maty.Envelope`, which carries the
  session it belongs to, the role it is addressed to and the role it is sent from.

  As explained above, to identify what message can currently be processed according to the session type,
  we need to look at our suspended handlers, and to do that we need the `session_id` and `to` from a given message.
  The `handlers` map will return an expected role and if the `from` of the message we're currently inspecting matches,
  then we process this message.
  """

  alias Maty.{Envelope, Session, Types}
  alias Maty.DSL.State

  require Logger

  @callback on_link(args :: any(), initial_state :: Types.maty_actor_state()) ::
              {:ok, Types.maty_actor_state()}

  defmacro __using__(_opts) do
    quote do
      use Maty.Hook
      use Maty.DSL
      import ST.Sigils
      require Maty.DSL
      require Maty.DSL.State
      @behaviour Maty.Actor

      @type actor_state :: Types.maty_actor_state()

      def start_link(args) do
        Maty.Actor.start_link(__MODULE__, args)
      end
    end
  end

  @spec start_link(module(), any()) :: {:ok, pid()}
  def start_link(module, args) do
    pid = spawn_link(fn -> init_and_run(module, args) end)

    {:ok, pid}
  end

  @spec init_and_run(module(), any()) :: no_return()
  defp init_and_run(module, args) do
    initial_state = State.new()

    {:ok, actor_state} = module.on_link(args, initial_state)

    loop(module, actor_state, [])
  end

  @spec loop(module(), State.t(), list(Envelope.t())) :: no_return()
  defp loop(module, actor_state, stash) do
    traverse_stash(module, actor_state, stash, [])
  end

  # Since processing a message progresses the session (via suspend or done)
  # we must then loop back to the start of the stash as messages which previously were unprocessable, may now be processable.
  # This is the common case: a message is stashed because its sender wasn't expected yet and becomes processable once the session moves on.
  @spec traverse_stash(module(), State.t(), list(Envelope.t()), list(Envelope.t())) :: no_return()
  defp traverse_stash(module, actor_state, [envelope | rest], skipped) do
    if can_process?(actor_state, envelope) do
      updated_actor_state = process_message(module, actor_state, envelope)
      loop(module, updated_actor_state, skipped ++ rest)
    else
      traverse_stash(module, actor_state, rest, skipped ++ [envelope])
    end
  end

  defp traverse_stash(module, actor_state, [], stash) do
    # in this clause we've checked every message in the stash and no handler can process any of them
    # so we take the first message in our mailbox
    receive_next(module, actor_state, stash)
  end

  # If we traverse the entire stash and find no message that any of our currently suspended handlers can process
  # we move on to processing messages from our mailbox. A similar process is done here.
  # We inspect which session and to which role this message was addressed and check whether the suspended handler can process this message.
  # If it can, we process the message and loop back to the start, otherwise we stash this message and then loop back to the start.
  @spec receive_next(module(), State.t(), list(Envelope.t())) :: no_return()
  defp receive_next(module, actor_state, stash) do
    receive do
      {:maty_message, %Envelope{} = envelope} ->
        if can_process?(actor_state, envelope) do
          updated_actor_state = process_message(module, actor_state, envelope)
          loop(module, updated_actor_state, stash)
        else
          loop(module, actor_state, stash ++ [envelope])
        end

      {:init_session, session_id, participants, init_token} ->
        updated_actor_state = init_role(module, actor_state, session_id, participants, init_token)
        loop(module, updated_actor_state, stash)

      # discard malformed messages
      other ->
        Logger.warning("[#{inspect(module)}] discarding unexpected message: #{inspect(other)}")
        loop(module, actor_state, stash)
    end
  end

  @spec process_message(module(), State.t(), Envelope.t()) :: State.t()
  defp process_message(module, actor_state, %Envelope{
         session_id: session_id,
         to: to,
         from: from,
         message: msg
       }) do
    session = actor_state.sessions[session_id]
    {handler_label, _} = session.handlers[to]

    result = apply(module, handler_label, [from, msg, actor_state, {session, to}])
    handle_result(module, result, session_id, to)
  end

  @spec init_role(
          module(),
          State.t(),
          Types.session_id(),
          %{Types.role() => pid()},
          Types.init_token()
        ) :: State.t()
  defp init_role(module, actor_state, session_id, participants, init_token) do
    # take the `role` and `callback` for the given `init_token`
    {{role, init_handler, args}, initial_state} = pop_in(actor_state.callbacks[init_token])

    # it's possible that at this stage the actor has already initiated the session with a different role
    # or maybe not, so we must ensure that a session exists
    updated_state = ensure_session(initial_state, session_id, participants)
    session = updated_state.sessions[session_id]

    result = apply(module, init_handler, [args, updated_state, {session, role}])
    handle_result(module, result, session_id, role)
  end

  @spec handle_result(
          module(),
          {:suspend, Types.handler_label(), State.t()} | {:done, State.t()},
          Types.session_id(),
          Types.role()
        ) :: State.t()
  defp handle_result(module, {:suspend, next_handler, actor_state}, session_id, role) do
    expected = module.__handler_expects__(next_handler)

    put_in(actor_state.sessions[session_id].handlers[role], {next_handler, expected})
  end

  defp handle_result(_module, {:done, actor_state}, session_id, role) do
    remaining = Map.delete(actor_state.sessions[session_id].handlers, role)

    if remaining == %{} do
      update_in(actor_state.sessions, &Map.delete(&1, session_id))
    else
      put_in(actor_state.sessions[session_id].handlers, remaining)
    end
  end

  @spec can_process?(State.t(), Envelope.t()) :: boolean()
  defp can_process?(actor_state, envelope) do
    with {:ok, session} <- Map.fetch(actor_state.sessions, envelope.session_id),
         {:ok, {_, expected_role}} <- Map.fetch(session.handlers, envelope.to) do
      expected_role == envelope.from
    else
      :error -> false
    end
  end

  @spec ensure_session(State.t(), Types.session_id(), %{Types.role() => pid()}) :: State.t()
  defp ensure_session(actor_state, session_id, participants) do
    %{
      actor_state
      | sessions:
          Map.put_new(actor_state.sessions, session_id, Session.new(session_id, participants))
    }
  end
end
