defmodule Maty.Actor do
  alias Maty.Types
  alias Maty.DSL.State

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

    loop(module, actor_state)
  end

  def traverse_stash(module, %State{stash: []} = actor_state, stash) do
    # if we get to here, it means our big stash is empty then we should try and read a message from our mailbox

    receive do
      {:maty_message, session_id, to, from, msg} ->
        # so I know for sure that the stash has nothing of interest, which means I only care about exit conditions  II and III
        {_, _, expected_role} = next_receive_in_session(actor_state, session_id, to)

        updated_actor_state =
          if from == expected_role do
            # exit condition II
            # the current message is compatible, so we process it
            process_message(module, %{actor_state | stash: stash}, {session_id, to, from, msg})
          else
            # exit condition III
            # not the current message either, so just stash and loop
            put_in(actor_state, [:stash], stash ++ [{session_id, to, from, msg}])
          end

        loop(module, updated_actor_state)

      # thoughts for later:
      # this kinda means that we may wait a while before we initialise a session
      # ig if we wanted to prioritise this we would have a receive that catches init messages up top
      # and just buffers everything else (?) or just loops
      {:init_session, session_id, participants, init_token} ->
        partial_session = %{
          id: session_id,
          participants: participants,
          handlers: %{},
          local_state: %{}
        }

        initial_actor_state = put_in(actor_state, [:sessions, session_id], partial_session)

        {{role, init_handler, args}, initial_actor_state} =
          pop_in(initial_actor_state, [:callbacks, init_token])

        updated_actor_state =
          case apply(module, init_handler, [args, initial_actor_state, {partial_session, role}]) do
            {:suspend, handler_name, intermediate_state} ->
              expected_role = module.__handler_expects__(handler_name)

              put_in(
                intermediate_state,
                [:sessions, session_id, :handlers, role],
                {handler_name, expected_role}
              )

            {:done, intermediate_state} ->
              update_in(intermediate_state, [:sessions], &Map.delete(&1, session_id))
          end

        loop(module, %{updated_actor_state | stash: stash})

      # discard malformed messages
      _ ->
        loop(module, %{actor_state | stash: stash})
    end
  end

  def traverse_stash(
        module,
        %State{stash: [{session_id, to, from, _msg} = m | rest]} = actor_state,
        traversed_stash
      ) do
    {_, _, expected_role} = next_receive_in_session(actor_state, session_id, to)

    if from == expected_role do
      # we can process this message and loop back out

      # first we remove it from the stash
      intermediate_actor_state = put_in(actor_state, [:stash], traversed_stash ++ rest)

      # then we actually process the message
      updated_actor_state = process_message(module, intermediate_actor_state, m)

      # then we loop back to the start
      loop(module, updated_actor_state)
    else
      traverse_stash(
        module,
        %{actor_state | stash: rest},
        traversed_stash ++ [m]
      )
    end

    # otherwise we continue on to check the next message
  end

  @spec loop(module(), State.t()) :: no_return()
  def loop(module, actor_state) do
    # {
    #    id: SessionID,
    #    handlers: Map<Role, (HandlerLabel, Role)>,
    #    participants: Map<Role, PID>,
    #    stash: List<(Role, Role, Message)>,
    # }

    # Let's say that this actor is a participant in multiple sessions S_i and each session keeps its own stash Q
    #     > so if some actor A takes part in two sessions we would identify the stashes as S_1.Q and S_2.Q
    #
    # An actor on the BEAM however only has a single mailbox so messages only arrive in one mailbox M.
    #
    # It's important to note that in each Session an actor may play multiple roles. Hence when we suspend we do so
    # for a given role.
    # So when we want to figure out if we can process some next message what we ought to do is:
    #
    # look at our stash
    # for each message in the stash we look at the role of the actor it was addressed to.
    # then we lookup for that role the handler it has suspended with/to.
    # if the suspended handler can process this message we go ahead and process it
    # otherwise we move on to the next message in the stash and repeat the process (??) until we have processed all the messages in the stash
    # at which point we move on and look at the mailbox?
    #
    # this doesn't seem right...
    #
    #
    # Actually let's say that this actor is a participant in multiple sessions S_i and rather than keeping a stash per session
    # we keep one central stash keyed by `session_id` and `to` which makes keying into the actor state and grabbing out
    # the handler we want

    traverse_stash(module, actor_state, [])
  end

  @spec process_message(
          module(),
          State.t(),
          {Types.session_id(), Types.role(), Types.role(), Types.message()}
        ) :: State.t()
  defp process_message(
         module,
         actor_state,
         {session_id, to, from, msg}
       ) do
    {session, handler_label, _} = next_receive_in_session(actor_state, session_id, to)

    case apply(module, handler_label, [from, msg, actor_state, {session, to}]) do
      {:suspend, next, intermediate_state} ->
        expected = module.__handler_expects__(next)

        put_in(
          intermediate_state,
          [:sessions, session_id, :handlers, to],
          {next, expected}
        )

      {:done, intermediate_state} ->
        update_in(intermediate_state, [:sessions], &Map.delete(&1, session_id))
    end
  end

  defp next_receive_in_session(actor_state, session_id, to) do
    session = actor_state.sessions[session_id]
    {handler_label, expected_role} = session.handlers[to]

    {session, handler_label, expected_role}
  end
end
