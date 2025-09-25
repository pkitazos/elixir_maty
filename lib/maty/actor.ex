defmodule Maty.Actor do
  alias Maty.{Types, Utils}

  # potentially make this a macro as well, can call it something like on_link or on_spawn or on_start
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
        # to    -> my role
        # from  -> recipient role
        session = actor_state.sessions[session_id]

        handler_label = session.handlers[to]

        handler_info = Utils.Env.get_map(module, :delta_M) |> Map.fetch!(handler_label)
        {handler, expected_role} = handler_info.function

        # we currently only check the role, but should also check the session type associated with this handler
        # to see if there is a branch which expects a message with this label as one of the branches
        if from == expected_role do
          updated_actor_state =
            case apply(module, handler, [msg, from, actor_state, {session, to}]) do
              {:suspend, next, intermediate_state} ->
                put_in(intermediate_state, [:sessions, session.id, :handlers, to], next)

              {:done, intermediate_state} ->
                update_in(intermediate_state, [:sessions], &Map.delete(&1, session.id))
            end

          loop(module, updated_actor_state)
        else
          send(self(), {:maty_message, session.id, to, msg})
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

        # todo: decide if this is global or local state
        {:suspend, handler_info, intermediate_state} =
          init_handler.(module, {partial_session, role}, initial_actor_state)

        updated_actor_state =
          put_in(intermediate_state, [:sessions, session_id, :handlers, role], handler_info)

        loop(module, updated_actor_state)

      # discard malformed messages
      _ ->
        loop(module, actor_state)
    end
  end
end
