defmodule Maty.Runtime.Session do
  @moduledoc """
  A Maty session an actor is participating in. Holds the handler suspended for each role,
  an address book of each participant to their PID, and the actor's session-local state
  """

  alias Maty.Types

  @enforce_keys [:id, :roles, :participants]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: Types.session_id(),
          # the key is the role this actor plays in the session, the paired role is the one
          # the suspended handler expects to receive from (see `__handler_expects__`)
          roles: %{
            # maybe this tuple could also be a map... or maybe I'm overdoing it with the maps
            Types.role() => %{handler: {Types.handler_label(), Types.role()}, state: term()}
            #                      figuring out how to type this will be interesting ^
          },
          participants: %{Types.role() => pid()}
        }

  @spec new(Types.session_id(), %{Types.role() => pid()}) :: t()
  def new(id, participants) do
    %__MODULE__{id: id, participants: participants, roles: %{}}
  end
end
