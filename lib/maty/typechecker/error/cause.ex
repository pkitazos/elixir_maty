defmodule Maty.Typechecker.Error.Cause do
  @moduledoc """
  The reason behind a user-facing `Maty.Typechecker.Error`, such as a type spec
  that failed to parse. Never reported on its own: it is embedded in the parent
  error's `details` under `:cause`, and rendered by the `Formatter`.

  Like an error, a cause is data: `kind` says what went wrong and `details` holds
  the values involved
  """

  @enforce_keys [:kind]
  defstruct [:kind, details: %{}]

  @type kind ::
          :unsupported_type_constructor
          | :unknown_type_constructor
          | :heterogeneous_list
          | :invalid_maty_state

  @type t :: %__MODULE__{kind: kind(), details: map()}
end
