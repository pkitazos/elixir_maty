defmodule Maty.DSL.State do
  @moduledoc """
  The state of a Maty actor, passed to every handler. Holds the sessions the actor is
  participating in, and the init handler registered under each pending init token

  Inside a handler, `get/1` and `set/2` read and write the local state of the session
  the handler is running in
  """

  alias Maty.{Session, Types}

  @enforce_keys [:sessions, :callbacks]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sessions: %{Types.session_id() => Session.t()},
          callbacks: %{Types.init_token() => {Types.role(), Types.handler_label(), any()}}
        }

  def new do
    %Maty.DSL.State{sessions: %{}, callbacks: %{}}
  end

  def set(state, local_state, {session, _}) do
    put_in(state.sessions[session.id].local_state, local_state)
  end

  defmacro set(state, local_state) do
    quote do
      Maty.DSL.State.set(unquote(state), unquote(local_state), var!(session_ctx))
    end
  end

  @spec internal_get(t(), Types.session_ctx()) :: map()
  def internal_get(state, {session, _}) do
    get_in(state.sessions[session.id].local_state)
  end

  defmacro get(state) do
    quote do
      Maty.DSL.State.internal_get(unquote(state), var!(session_ctx))
    end
  end
end
