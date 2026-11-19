defmodule Maty.Hook do
  # todo: can probably merge into Typechecker at some point
  defmacro __using__(_opts) do
    quote do
      @compile :debug_info

      # ephemeral annotations
      for attr <- [:init_handler, :handler, :handler_stub, :spec],
          do: Module.register_attribute(__MODULE__, attr, accumulate: false, persist: false)

      # attribute stores
      for attr <- [:st, :session_type, :handler_errors, :global_state_type, :local_state_type],
          do: Module.register_attribute(__MODULE__, attr, accumulate: true, persist: true)

      # one record per clause, which beocmes the input to `Signatures.build/4` @before_compile
      Module.register_attribute(__MODULE__, :maty_clauses, accumulate: true, persist: false)

      @on_definition Maty.Typechecker
      @before_compile Maty.Typechecker
      @after_compile Maty.Typechecker
    end
  end
end
