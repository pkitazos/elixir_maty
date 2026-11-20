defmodule Maty.Typechecker.Ctx do
  alias Maty.Types

  # `init/1` sets every field, the defaults let tests build a `Ctx` with only the fields they use
  @enforce_keys [:module]
  defstruct [
    :module,
    meta: [],
    signatures: %{},
    declared_state_types: %{global: nil, local: %{}},
    handler_state_type: nil
  ]

  @type t :: %__MODULE__{
          module: module(),
          meta: keyword(),
          # the state type of the handler whose body is being checked, `nil` outside a handler
          handler_state_type: Types.T.t() | nil,
          # the module's `global_state` / `local_state` declarations
          declared_state_types: Types.state_types(),
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
      handler_state_type: nil,
      declared_state_types: Module.get_attribute(env.module, :maty_state_types),
      signatures: Module.get_attribute(env.module, :maty_signatures)
    }
  end

  def get_localised_state_type(ctx), do: {:map_record, %{ctx.declared_state_types | local: nil}}

  def get_localised_state_type(ctx, role),
    do: {:map_record, %{ctx.declared_state_types | local: ctx.declared_state_types.local[role]}}
end
