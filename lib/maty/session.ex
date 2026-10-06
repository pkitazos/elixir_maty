defmodule Maty.Session do
  @moduledoc """
  A Maty session an actor is participating in. Holds the handler suspended for each role,
  an address book of each participant to their PID, and the actor's session-local state
  """

  alias Maty.Types

  @enforce_keys [:id, :handlers, :participants, :local_state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: Types.session_id(),
          # the key is the role this actor plays in the session, the paired role is the one
          # the suspended handler expects to receive from (see `__handler_expects__`)
          handlers: %{Types.role() => {Types.handler_label(), Types.role()}},
          participants: %{Types.role() => pid()},
          local_state: map()
        }

  @spec new(Types.session_id(), %{Types.role() => pid()}) :: t()
  def new(id, participants) do
    %__MODULE__{id: id, participants: participants, handlers: %{}, local_state: %{}}
  end
end
