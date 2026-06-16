defmodule Maty.Typechecker.Error.NameResolution do
  @moduledoc """
  Errors for referenced names that do not resolve to anything in the current scope.
  """
  alias Maty.Typechecker.Error

  def variable_not_exist(module, meta, var) do
    %Error{
      category: :name_resolution,
      kind: :variable_not_exist,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{var: var}
    }
  end
end
