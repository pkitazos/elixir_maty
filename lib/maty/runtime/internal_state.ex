defmodule Maty.Runtime.InternalState do
  @moduledoc """
  The state of a Maty actor, passed to every handler. Holds the sessions the actor is
  participating in, and the init handler registered under each pending init token
  """

  alias Maty.Types
  alias Maty.Runtime.Session

  @enforce_keys [:sessions, :callbacks, :global_actor_state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sessions: %{Types.session_id() => Session.t()},
          callbacks: %{Types.init_token() => Types.registration_info()},
          global_actor_state: term()
          #                   ^ figure out how to type this
        }

  # todo: could be named `new_from` or just `from` or `new_with`
  @spec new(term()) :: t()
  def new(global_actor_state) do
    %Maty.Runtime.InternalState{
      sessions: %{},
      callbacks: %{},
      global_actor_state: global_actor_state
    }
  end
end
