defmodule Maty.Typechecker.Ctx do
  alias Maty.Types

  @enforce_keys [:module, :meta, :roles, :signatures]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          roles: list(Types.role()),
          signatures: %{
            # reuse types from `Maty.Types` instead of redefining them all over the place
            atom() =>
              {:handler, :message, Types.role(), ST.t()}
              | {:handler, :init, Types.role(), Types.T.t(), ST.t()},
            {module(), atom(), arity()} => {:function, [Types.T.t()], Types.T.t()}
          }
        }

  # todo: add spec
  def init(env) do
    %__MODULE__{
      module: env.module,
      meta: [line: env.line],
      roles: Module.get_attribute(env.module, :maty_roles),
      signatures: Module.get_attribute(env.module, :maty_signatures)
    }
  end
end
