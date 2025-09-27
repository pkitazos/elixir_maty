defmodule Maty.Utils do
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
      try do
        # Try compile-time access first
        Module.get_attribute(module, attribute)
      rescue
        ArgumentError ->
          # Module is already compiled, use runtime access
          case module.__info__(:attributes) do
            attributes when is_list(attributes) ->
              Keyword.get(attributes, attribute)

            _ ->
              nil
          end
      end
    end

    def get_map(module, attribute) do
      try do
        # Try compile-time access first
        Module.get_attribute(module, attribute) |> Enum.into(%{})
      rescue
        ArgumentError ->
          # Module is already compiled, use runtime access
          case module.__info__(:attributes) do
            attributes when is_list(attributes) ->
              case Keyword.get(attributes, attribute) do
                nil -> %{}
                list when is_list(list) -> Enum.into(list, %{})
                other -> %{default: other}
              end

            _ ->
              %{}
          end
      end
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

  # this is explicitly for debugging purposes, and should absolutely be removed from any final product
  def stack_trace(_num), do: :ok
  # def stack_trace(num), do: Logger.debug("[#{num}]", ansi_color: :light_green)
end
