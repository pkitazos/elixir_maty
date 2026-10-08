defmodule Maty.Typechecker.Ctx do
  alias Maty.Types

  @enforce_keys [:module, :meta, :roles]
  defstruct [:module, :meta, :roles, delta_M: %{}, delta_I: %{}, psi: %{}]

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          roles: list(Types.role()),
          delta_M: %{
            Types.handler_label() => %{function: {atom(), arity()}, st: ST.t()}
          },
          delta_I: %{
            Types.handler_label() => %{function: {atom(), arity()}, st: ST.t()}
          },
          psi: %{{atom(), arity()} => [{[Types.T.t()], Types.T.t()}]}
        }
end
