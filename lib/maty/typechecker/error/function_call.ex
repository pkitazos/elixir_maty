defmodule Maty.Typechecker.Error.FunctionCall do
  alias Maty.Typechecker.Error

  def function_not_exist(module, meta, func_id) do
    %Error{
      category: :function_call,
      kind: :function_not_exist,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id}
    }
  end

  # a handler was called like a regular function (at its real arity)
  def handler_called_directly(module, meta, func_id, handler_kind)
      when handler_kind in [:init, :message] do
    %Error{
      category: :function_call,
      kind: :handler_called_directly,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, handler_kind: handler_kind}
    }
  end

  def function_altered_session_state(module, meta, func_id, final_state) do
    %Error{
      category: :function_call,
      kind: :function_altered_session_state,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, final_state: final_state}
    }
  end

  def wrong_number_of_clauses(module, meta, func_id, expected: expected, got: got) do
    %Error{
      category: :function_call,
      kind: :wrong_number_of_clauses,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, expected: expected, got: got}
    }
  end

  def wrong_number_of_specs(module, meta, func_id, expected: expected, got: got)
      when is_integer(expected) or is_list(expected) do
    %Error{
      category: :function_call,
      kind: :wrong_number_of_specs,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, expected: expected, got: got}
    }
  end

  # `f.(...)` was called with a different number of arguments than the function takes
  def application_arity_mismatch(module, meta, expected: expected, got: got) do
    %Error{
      category: :function_call,
      kind: :application_arity_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
    }
  end
end
