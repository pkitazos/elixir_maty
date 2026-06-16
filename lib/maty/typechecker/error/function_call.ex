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

  def arity_mismatch(module, meta, func_id, expected: expected, got: got) do
    %Error{
      category: :function_call,
      kind: :arity_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, expected: expected, got: got}
    }
  end

  def no_matching_function_clause(module, meta, func_id, actual_arg_types) do
    %Error{
      category: :function_call,
      kind: :no_matching_function_clause,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id, arg_types: actual_arg_types}
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

  def wrong_number_of_clauses(module, func_id, expected: expected, got: got) do
    %Error{
      category: :function_call,
      kind: :wrong_number_of_clauses,
      module: module,
      details: %{func_id: func_id, expected: expected, got: got}
    }
  end

  def wrong_number_of_specs(module, func_id, expected: expected, got: got) do
    %Error{
      category: :function_call,
      kind: :wrong_number_of_specs,
      module: module,
      details: %{func_id: func_id, expected: expected, got: got}
    }
  end
end
