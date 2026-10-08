defmodule Maty.Protocol do
  alias Maty.Types

  @callback __roles__() :: [Types.role()]
  @callback __projection__(Types.role()) :: ST.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Maty.Protocol

      import ST.Sigils
      Module.register_attribute(__MODULE__, :projection, accumulate: true)
      @before_compile Maty.Protocol
    end
  end

  defmacro __before_compile__(env) do
    all_projections = Module.get_attribute(env.module, :projection) |> Enum.reverse()

    if all_projections == [] do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "protocol #{inspect(env.module)} declares no projections"
    end

    roles = Enum.map(all_projections, fn {role, _} -> role end)

    duplicated_roles = Enum.uniq(roles -- Enum.uniq(roles))

    if duplicated_roles != [] do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "multiple projections for: #{inspect(duplicated_roles)}"
    end

    projection_clauses =
      for {role, projection} <- all_projections do
        quote do
          def __projection__(unquote(role)) do
            unquote(Macro.escape(projection))
          end
        end
      end

    quote do
      @impl Maty.Protocol
      def __roles__(), do: unquote(roles)

      @impl Maty.Protocol
      unquote_splicing(projection_clauses)
    end
  end
end
