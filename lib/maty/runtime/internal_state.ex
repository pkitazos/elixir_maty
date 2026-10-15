defmodule Maty.Runtime.InternalState do
  @moduledoc """
  The state of a Maty actor, passed to every handler. Holds the sessions the actor is
  participating in, and the init handler registered under each pending init token

  Inside a handler, `get/1` and `set/2` read and write the local state of the session
  the handler is running in
  """

  alias Maty.Types
  alias Maty.Runtime.Session

  @enforce_keys [:sessions, :callbacks, :global_actor_state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sessions: %{Types.session_id() => Session.t()},
          callbacks: %{Types.init_token() => {Types.role(), Types.handler_label(), any()}},
          global_actor_state: term()
          #                   ^ figure out how to type this
        }

  @spec new(term()) :: t()
  # could be named `new_from` or just `from` or `new_with`
  def new(global_actor_state) do
    %Maty.Runtime.InternalState{
      sessions: %{},
      callbacks: %{},
      global_actor_state: global_actor_state
    }
  end

  # not sure what this should be called
  def get_actor_state(s, session_id, role) do
    %{
      global: s.global_actor_state,
      local: s.sessions[session_id].roles[role].state
    }
  end
end
