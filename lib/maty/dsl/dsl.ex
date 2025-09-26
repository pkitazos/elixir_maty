defmodule Maty.DSL do
  alias Maty.DSL
  alias Maty.Types

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

  ## Parameters
    - `ap_pid`: The PID of the Access Point process.
    - `role`: The role this actor will play in the session (atom).
    - `reg_info`: A keyword list containing registration details,
      specifically `[callback: handler_name, args: init_args]`.
      - `handler_name`: The atom name of the `init_handler` to be called
        when the session starts.
      - `init_args`: The arguments to pass to the `init_handler`.
    - `state`: The current actor state (`maty_actor_state`).

  ## Returns
    - `{:ok, updated_state}` on successful registration.
    - `{:error, :invalid_registration_info}` if `reg_info` is malformed.
  """
  @spec register(
          ap_pid :: pid(),
          role :: Types.role(),
          reg_info :: keyword(),
          state :: Types.maty_actor_state()
        ) :: {:ok, Types.maty_actor_state()} | {:error, atom()}
  def register(ap_pid, role, reg_info, state) do
    with {:ok, handler_name} when is_atom(handler_name) <- Keyword.fetch(reg_info, :callback),
         {:ok, init_args} <- Keyword.fetch(reg_info, :args) do
      # identified the suspended callback

      init_token = make_ref()
      Kernel.send(ap_pid, {:register, role, self(), init_token})

      callback = fn module, state, session_ctx ->
        apply(module, handler_name, [init_args, state, session_ctx])
      end

      updated_state = put_in(state, [:callbacks, init_token], {role, callback})
      {:ok, updated_state}
    else
      :error -> {:error, :invalid_registration_info}
    end
  end

  @spec internal_send({Types.session(), Types.role()}, Types.role(), {atom(), any()}) :: atom()
  def internal_send({session, from}, to, msg) do
    Kernel.send(session.participants[to], {:maty_message, session.id, to, from, msg})
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
