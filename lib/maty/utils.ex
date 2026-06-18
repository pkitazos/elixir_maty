defmodule Maty.Utils do
  require Logger
  # move
  # these are display functions for printing function ids
  # this should probably move, change and be renamed,
  # but it's good that it exists somewhere
  def to_func({name, arity}), do: "#{name}/#{arity}"
  def to_func(name: name, arity: arity), do: "#{name}/#{arity}"

  # this whole module needs some tlc
  # it's meant to make environment management simpler,
  # but right now it's just complicating things
  defmodule Env do
    def setup(module, attribute) do
      Module.register_attribute(module, attribute, accumulate: true, persist: true)
    end

    def get(module, attribute) do
      Module.get_attribute(module, attribute)
    end

    def get_map(module, attribute) do
      Module.get_attribute(module, attribute) |> Enum.into(%{})
    end

    def add_at_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, val, fn _ -> val end)
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    def prepend_to_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, [val], fn vals -> [val | vals] end)
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    def remove_from_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, [], &Enum.filter(&1, fn x -> x != val end))
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    defp rewrite(module, attribute, entries) do
      Module.delete_attribute(module, attribute)

      for entry <- entries do
        Module.put_attribute(module, attribute, entry)
      end
    end
  end

  if Application.compile_env(:maty, :debug_stack_trace, false) do
    defmacro stack_trace do
      quote do
        require Logger
        {func_name, func_arity} = __ENV__.function

        Logger.debug("[#{inspect(__MODULE__)}.#{func_name}/#{func_arity}:#{__ENV__.line}]")
      end
    end
  else
    defmacro stack_trace do
      :ok
    end
  end

  # Wrapper around `def` that injects a `stack_trace()` call at the top of each clause.
  # When MATY_DEBUG=1, logs the module, function, arity, and line number.
  # When debug is off, `stack_trace()` compiles to `:ok` and is optimized away.
  defmacro deftc(call, do: body) do
    quote do
      def unquote(call) do
        # use fully qualified name, because when the macro is expanded `stack_trace` may not be in scope
        Maty.Utils.stack_trace()
        unquote(body)
      end
    end
  end
end
