defmodule Maty.Typechecker.Error.Cause do
  @moduledoc """
  The reason behind a user-facing `Maty.Typechecker.Error`, such as a type spec
  that failed to parse. Never reported on its own: it is embedded in the parent
  error's `details` under `:cause`, and unpacked by the `Formatter`.
  """

  defstruct [:title, :opts, :message]

  @type t :: %__MODULE__{
          title: binary(),
          opts: binary(),
          message: binary()
        }
end
