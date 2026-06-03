defmodule Maty.Typechecker.Ctx do
  @enforce_keys [:module, :meta]
  defstruct [:module, :meta, delta_M: %{}, delta_I: %{}, psi: %{}]

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          delta_M: %{atom() => term()},
          delta_I: %{atom() => term()},
          psi: %{term() => term()}
        }
end
