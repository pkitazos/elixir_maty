defmodule Maty.DSL do
  alias Maty.DSL
  alias Maty.{Types, Envelope}

  defmacro __using__(_opts) do
    quote do
      import Maty.DSL.Handlers, only: [handler: 5, init_handler: 4, on_link: 3]
      require Maty.DSL
      alias Maty.DSL, as: MatyDSL
      require Maty.DSL.State
      alias Maty.DSL.State
    end
  end

  @doc """
  Registers an actor instance with the Access Point (AP).

  This function sends a registration message to the AP and stores
  initialisation information (role, handler name, initial arguments)
  in the actor's state, associated with a unique token.

  The handler name and its arguments together stand in for the callback closure of the Maty calculus
  when the session starts, the init handler is called with: `args`, the actor state and the session context.

  ## Parameters
    - `ap_pid`: The PID of the Access Point process.
    - `role`: The role this actor will play in the session (atom).
    - `handler`: The name of the `init_handler` to be called when the session starts, as a literal atom
    - `args`: The single value passed to the `init_handler` (use a tuple for several values, and `nil` for none).
    - `state`: The current actor state (`maty_actor_state`).

  ## Returns
    - `{:ok, updated_state}`.
  """
  @spec register(
          ap_pid :: pid(),
          role :: Types.role(),
          handler :: atom(),
          # no way to get around this `term()` I don't think
          args :: term(),
          state :: Types.maty_actor_state()
        ) :: {:ok, Types.maty_actor_state()}
  def register(ap_pid, role, handler, args, state) do
    # the init token identifies the suspended callback
    init_token = make_ref()
    Kernel.send(ap_pid, {:register, role, self(), init_token})

    updated_state = put_in(state, [:callbacks, init_token], {role, handler, args})
    {:ok, updated_state}
  end

  @spec internal_send({Types.session(), Types.role()}, Types.role(), Types.message()) :: atom()
  def internal_send({session, from}, to, msg) do
    envelope = %Envelope{session_id: session.id, to: to, from: from, message: msg}
    Kernel.send(session.participants[to], {:maty_message, envelope})
    :ok
  end

  defmacro send(recipient, message) do
    quote do
      DSL.internal_send(var!(session_ctx), unquote(recipient), unquote(message))
    end
  end

  defmacro suspend(next_handler, state) do
    quote do
      throw({:suspend, unquote(next_handler), unquote(state)})
    end
  end

  defmacro done(state) do
    quote do
      throw({:done, unquote(state)})
    end
  end
end
