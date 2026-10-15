defmodule Maty.Runtime.InternalState do
  @moduledoc """
  The state of a Maty actor, passed to every handler. Holds the sessions the actor is
  participating in, and the init handler registered under each pending init token
  """

  alias Maty.Types
  alias Maty.Runtime.Session

  @enforce_keys [:sessions, :pending_registrations, :global_actor_state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sessions: %{Types.session_id() => Session.t()},
          pending_registrations: %{Types.init_token() => Types.registration_info()},
          global_actor_state: Types.global_state()
          #                   ^ figure out how to type this
        }

  # todo: could be named `new_from` or just `from` or `new_with`
  @spec new(Types.global_state()) :: t()
  def new(global_actor_state) do
    %Maty.Runtime.InternalState{
      sessions: %{},
      pending_registrations: %{},
      global_actor_state: global_actor_state
    }
  end
end
