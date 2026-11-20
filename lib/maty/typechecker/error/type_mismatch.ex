defmodule Maty.Typechecker.Error.TypeMismatch do
  alias Maty.Typechecker.Error

  def logical_operator_requires_boolean(module, meta, operator, operand_type) do
    %Error{
      category: :type_mismatch,
      kind: :logical_operator_requires_boolean,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{operator: operator, operand_type: operand_type}
    }
  end

  # unary minus `-x` on a non-number
  def arithmetic_operator_requires_number(module, meta, operator, operand_type) do
    %Error{
      category: :type_mismatch,
      kind: :arithmetic_operator_requires_number,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{operator: operator, operand_type: operand_type}
    }
  end

  # `register` was given something that is not an init handler or `suspend` was something that is not a message handler
  def handler_expected(module, meta, expected_kind, got_type)
      when expected_kind in [:init, :message] do
    %Error{
      category: :type_mismatch,
      kind: :handler_expected,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected_kind: expected_kind, got: got_type}
    }
  end

  # a tuple literal checked against a tuple type has a different number of elements
  def tuple_arity_mismatch(module, meta, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :tuple_arity_mismatch,
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

  def case_branches_incompatible(module, meta, branches) do
    %Error{
      category: :type_mismatch,
      kind: :case_branches_incompatible,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{branches: branches}
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

  # a part of a string had the wrong type
  # `segment` is :interpolation for a `#{...}` value or :concatenation for a `<>` operand
  def string_segment_type_mismatch(module, meta, segment, expected: expected, got: got)
      when segment in [:interpolation, :concatenation] do
    %Error{
      category: :type_mismatch,
      kind: :string_segment_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{segment: segment, expected: expected, got: got}
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

  # A record update `%{m | k: v}` was applied to a value that is not a map record
  def map_update_not_record(module, meta, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :map_update_not_record,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # A record update `%{m | k: v}` names a key the record does not have (`|` raises a KeyError at runtime)
  def map_update_key_not_found(module, meta, key, record_type) do
    %Error{
      category: :type_mismatch,
      kind: :map_update_key_not_found,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{key: key, record: record_type}
    }
  end

  # A field access `m.k` was applied to a value that is not a map record
  def field_access_not_record(module, meta, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :field_access_not_record,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # A field access `m.k` names a key the record does not have (`m.k` raises a KeyError at runtime)
  def field_access_key_not_found(module, meta, key, record_type) do
    %Error{
      category: :type_mismatch,
      kind: :field_access_key_not_found,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{key: key, record: record_type}
    }
  end

  # A record literal `%{k1: v1, ...}` gives the same label more than once (labels must be disinct)
  def record_duplicate_label(module, meta, label) do
    %Error{
      category: :type_mismatch,
      kind: :record_duplicate_label,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{label: label}
    }
  end

  # A record literal or update uses `true`, `false` or `nil` as a label
  def invalid_record_label(module, meta, label) do
    %Error{
      category: :type_mismatch,
      kind: :invalid_record_label,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{label: label}
    }
  end

  # A record literal checked against a record type leaves out some of the type's fields (all fields are required)
  def record_missing_fields(module, meta, labels, record_type) do
    %Error{
      category: :type_mismatch,
      kind: :record_missing_fields,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{labels: labels, record: record_type}
    }
  end

  # A record literal checked against a record type gives a field the type does not have
  def record_unexpected_field(module, meta, label, record_type) do
    %Error{
      category: :type_mismatch,
      kind: :record_unexpected_field,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{label: label, record: record_type}
    }
  end

  # -- dicts

  # a dict key has a type that is not a base type
  def dict_key_not_base_type(module, meta, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :dict_key_not_base_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # `Map.put/3`, `Map.fetch!/2` or `Map.delete/2` was applied to a value that is not a dict
  def dict_op_not_dict(module, meta, op, got: got) when op in [:put, :fetch!, :delete] do
    %Error{
      category: :type_mismatch,
      kind: :dict_op_not_dict,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{op: op, got: got}
    }
  end

  # a dict operation was given a key (or for `Map.put/3` a value) whose type is not the dict's
  def dict_arg_type_mismatch(module, meta, op, argument, expected: expected, got: got)
      when op in [:put, :fetch!, :delete] and argument in [:key, :value] do
    %Error{
      category: :type_mismatch,
      kind: :dict_arg_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{op: op, argument: argument, expected: expected, got: got}
    }
  end

  # -- functions

  # `f.(...)` where `f` is not a function
  def not_a_function(module, meta, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :not_a_function,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # `f.(...)` was given an argument whose type is not the function's parameter type
  # `position` is 1-based
  def function_arg_type_mismatch(module, meta, position, expected: expected, got: got)
      when is_integer(position) do
    %Error{
      category: :type_mismatch,
      kind: :function_arg_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{position: position, expected: expected, got: got}
    }
  end

  # an anonymous function was checked against a type that is not a function type
  def lambda_not_expected(module, meta, expected: expected) do
    %Error{
      category: :type_mismatch,
      kind: :lambda_not_expected,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected}
    }
  end

  # an anonymous function was checked against a function type with a different number of parameters
  def lambda_arity_mismatch(module, meta, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :lambda_arity_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
    }
  end

  # --

  # an expression checked against a type synthesised a different one
  def expected(module, meta, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :expected,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
    }
  end
end
