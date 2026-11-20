defmodule Maty.Typechecker.Ctx do
  alias Maty.Types

  @enforce_keys [:module, :meta, :signatures, :state_types, :state_type]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          state_type: Types.T.t() | nil,
          # todo: replace with above or idk rename one of the two
          state_types: Types.state_types(),
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
      state_type: nil,
      state_types: Module.get_attribute(env.module, :maty_state_types),
      signatures: Module.get_attribute(env.module, :maty_signatures)
    }
  end
end
