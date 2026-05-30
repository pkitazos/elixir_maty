defmodule Maty.Actor do
  alias Maty.Types

  @callback on_link(args :: any(), initial_state :: Types.maty_actor_state()) ::
              {:ok, Types.maty_actor_state()}

  defmacro __using__(_opts) do
    quote do
      use Maty.Hook
      use Maty.DSL
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
    initial_state = %Maty.DSL.State{sessions: %{}, callbacks: %{}}

    {:ok, actor_state} = module.on_link(args, initial_state)

    loop(module, actor_state)
  end

  @spec loop(module(), Types.maty_actor_state()) :: no_return()
  defp loop(module, actor_state) do
    receive do
      # what happens if I receive a message from another Maty actor before I properly setup up my session?
      # perhaps do a similar thing where I send the message to the back of the queue and process it later?
      {:maty_message, session_id, to, from, msg} ->
        session = actor_state.sessions[session_id]
        {handler_label, expected_role} = session.handlers[to]

        if from == expected_role do
          updated_actor_state =
            case apply(module, handler_label, [from, msg, actor_state, {session, to}]) do
              {:suspend, next, intermediate_state} ->
                expected = module.__handler_expects__(next)
                put_in(intermediate_state, [:sessions, session.id, :handlers, to], {next, expected})

              {:done, intermediate_state} ->
                update_in(intermediate_state, [:sessions], &Map.delete(&1, session.id))
            end

          loop(module, updated_actor_state)
        else
          send(self(), {:maty_message, session.id, to, from, msg})
          loop(module, actor_state)
        end

      {:init_session, session_id, participants, init_token} ->
        partial_session = %{
          id: session_id,
          participants: participants,
          handlers: %{},
          local_state: %{}
        }

        initial_actor_state = put_in(actor_state, [:sessions, session_id], partial_session)

        {role, init_handler} = initial_actor_state.callbacks[init_token]

        {:suspend, handler_name, intermediate_state} =
          init_handler.(module, initial_actor_state, {partial_session, role})

        expected_role = module.__handler_expects__(handler_name)

        updated_actor_state =
          put_in(intermediate_state, [:sessions, session_id, :handlers, role], {handler_name, expected_role})

        loop(module, updated_actor_state)

      # discard malformed messages
      _ ->
        loop(module, actor_state)
    end
  end
end
