defmodule Maty.Hook do
  alias Maty.{Typechecker, Utils}

  defmacro __using__(_opts) do
    quote do
      import Maty.Hook

      # ephemeral annotations
      Module.register_attribute(__MODULE__, :init_handler, accumulate: false, persist: false)
      Module.register_attribute(__MODULE__, :handler, accumulate: false, persist: false)
      Module.register_attribute(__MODULE__, :handler_stub, accumulate: false, persist: false)
      Module.register_attribute(__MODULE__, :spec, accumulate: false, persist: false)

      # attribute stores
      Utils.Env.setup(__MODULE__, :st)
      Utils.Env.setup(__MODULE__, :delta_M)
      Utils.Env.setup(__MODULE__, :delta_I)
      Utils.Env.setup(__MODULE__, :psi)
      Utils.Env.setup(__MODULE__, :spec_errors)
      Utils.Env.setup(__MODULE__, :handler_errors)
      Utils.Env.setup(__MODULE__, :non_handler_defs)
      Utils.Env.setup(__MODULE__, :global_state_type)
      Utils.Env.setup(__MODULE__, :local_state_type)

      # one record per clause, which beocmes the input to `Signatures.build/3` @before_compile
      Module.register_attribute(__MODULE__, :maty_clauses, accumulate: true, persist: false)

      @compile :debug_info

      @on_definition Maty.Hook
      @before_compile Maty.Hook
      @after_compile Maty.Hook
    end
  end

  def __on_definition__(env, kind, name, args, guards, body) do
    Typechecker.handle_on_definition(env, kind, name, args, guards, body)
  end

  def __before_compile__(env) do
    Typechecker.handle_before_compile(env)
  end

  def __after_compile__(env, bytecode) do
    Typechecker.handle_after_compile(env, bytecode)
  end
end
