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
            Types.role() => %{
              handler: {Types.handler_label(), Types.role()},
              # todo: what actually goes here?
              state: Types.local_state()
            }
          },
          participants: Types.address_book()
        }

  @spec new(Types.session_id(), Types.address_book()) :: t()
  def new(id, participants) do
    %__MODULE__{id: id, participants: participants, roles: %{}}
  end
end
