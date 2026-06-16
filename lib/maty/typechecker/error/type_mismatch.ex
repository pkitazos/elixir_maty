defmodule Maty.Typechecker.Error.TypeMismatch do
  alias Maty.Typechecker.Error

  defp render_type(type) when is_atom(type), do: ":#{type}"
  defp render_type(type), do: "#{inspect(type)}"

  def logical_operator_requires_boolean(module, meta, operator, operand_type) do
    %Error{
      category: :type_mismatch,
      kind: :logical_operator_requires_boolean,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{operator: operator, operand_type: operand_type}
    }
  end

  def return_type_mismatch(module, meta, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :return_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
    }
  end

  def binary_operator_type_mismatch(module, meta, operator, lhs_type, rhs_type) do
    %Error{
      category: :type_mismatch,
      kind: :binary_operator_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{operator: operator, lhs: lhs_type, rhs: rhs_type}
    }
  end

  def logical_operator_type_mismatch(module, meta, operator, lhs_type, rhs_type) do
    %Error{
      category: :type_mismatch,
      kind: :logical_operator_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{operator: operator, lhs: lhs_type, rhs: rhs_type}
    }
  end

  def list_elements_incompatible(module, meta, element_types) do
    %Error{
      category: :type_mismatch,
      kind: :list_elements_incompatible,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{element_types: element_types}
    }
  end

  def case_branches_incompatible(module, meta, branches) do
    %Error{
      category: :type_mismatch,
      kind: :case_branches_incompatible,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{branches: branches}
    }
  end

  def invalid_maty_state_type(module, meta, %Error.Internal{} = internal) do
    %Error{
      category: :type_mismatch,
      kind: :invalid_maty_state_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{internal: internal}
    }
  end

  def invalid_maty_state_type(got_type) do
    %Error.Internal{
      title: "Invalid Maty State Type",
      opts: "Expected type: :maty_actor_state\nGot type: #{render_type(got_type)}",
      message: "Maty operations require a valid actor state type."
    }
  end

  def send_message_not_tuple(module, meta, got: message_ast) do
    %Error{
      category: :type_mismatch,
      kind: :send_message_not_tuple,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: message_ast}
    }
  end

  # A built-in (rn just: IO.puts + :timer.sleep) was called with an argument of the wrong type
  def builtin_arg_type_mismatch(module, meta, function, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :builtin_arg_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{function: function, expected: expected, got: got}
    }
  end
end
