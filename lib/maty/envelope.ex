defmodule Maty.Envelope do
  @moduledoc """
  A message as sent between Maty actors: it holds the message itself plus the
  session it belongs to and the roles it is addressed to and sent from
  """

  alias Maty.Types

  @enforce_keys [:session_id, :to, :from, :message]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          session_id: Types.session_id(),
          to: Types.role(),
          from: Types.role(),
          message: Types.message()
        }
end
