defmodule Maty.Typechecker.Ctx do
  alias Maty.Types

  @enforce_keys [:module, :meta, :roles]
  defstruct [:module, :meta, :roles, signatures: %{}, delta_M: %{}, delta_I: %{}, psi: %{}]

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          roles: list(Types.role()),

          # new Σ env/map
          signatures: %{
            atom() => {:handler, :message, ST.t()} | {:handler, :init, [Types.t()], St.t()},
            {module(), atom(), arity()} => {:function, [Types.t()], Types.t()}
          },

          # todo: deprecate
          delta_M: %{
            Types.handler_label() => %{function: {atom(), arity()}, st: ST.t()}
          },
          delta_I: %{
            Types.handler_label() => %{function: {atom(), arity()}, st: ST.t()}
          },
          psi: %{{atom(), arity()} => [{[Types.T.t()], Types.T.t()}]}
        }
end
