defmodule Maty.Typechecker.Delta do
  # this also needs some thought and care put into it
  def get_key_set(module, attribute) when attribute in [:delta_I, :delta_M] do
    Module.get_attribute(module, attribute) |> key_set()
  end

  def key_set(environment) do
    environment
    |> Enum.map(fn {_, x} -> x.function end)
    |> MapSet.new()
  end
end
