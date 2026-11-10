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

  def return_type_mismatch(module, meta, expected: expected, got: got) do
    %Error{
      category: :type_mismatch,
      kind: :return_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
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

  def invalid_maty_state_type(module, meta, %Error.Cause{} = cause) do
    %Error{
      category: :type_mismatch,
      kind: :invalid_maty_state_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{cause: cause}
    }
  end

  def invalid_maty_state_cause(got_type) do
    %Error.Cause{kind: :invalid_maty_state, details: %{got: got_type}}
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

  # MatyDSL.register/4 was called with an argument of the wrong type.
  # - `argument` names which arg was wrong
  # - `expected` is a type or (for the init handler args) the list of types its clauses accept
  def register_arg_type_mismatch(module, meta, argument, expected: expected, got: got)
      when argument in [:access_point, :init_handler_args] do
    %Error{
      category: :type_mismatch,
      kind: :register_arg_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{argument: argument, expected: expected, got: got}
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
