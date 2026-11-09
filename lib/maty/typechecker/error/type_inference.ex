defmodule Maty.Typechecker.Error.TypeInference do
  alias Maty.Typechecker.Error

  # a term whose type can only be checked, not synthesised, was used where no type is expected
  # `term` is :empty_list (`[]`), :empty_map (`%{}`) or :anonymous_function (`fn ... end`)
  def cannot_infer_type(module, meta, term)
      when term in [:empty_list, :empty_map, :anonymous_function] do
    %Error{
      category: :type_inference,
      kind: :cannot_infer_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{term: term}
    }
  end
end
