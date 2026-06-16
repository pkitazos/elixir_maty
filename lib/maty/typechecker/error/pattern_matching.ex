defmodule Maty.Typechecker.Error.PatternMatching do
  alias Maty.Typechecker.Error

  def conflicting_pattern_bindings(module, meta, conflicting_vars) do
    %Error{
      category: :pattern_matching,
      kind: :conflicting_pattern_bindings,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{conflicting_vars: conflicting_vars}
    }
  end

  def pattern_type_mismatch(module, meta, pattern: pattern, expected: expected, got: got) do
    %Error{
      category: :pattern_matching,
      kind: :pattern_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{pattern: pattern, expected: expected, got: got}
    }
  end

  def pattern_arity_mismatch(module, meta, pattern: pattern_type, expected: expected, got: got) do
    %Error{
      category: :pattern_matching,
      kind: :pattern_arity_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{pattern_type: pattern_type, expected: expected, got: got}
    }
  end

  def tuple_arity_mismatch(module, meta, pattern_arity: pattern_arity, expected: expected) do
    %Error{
      category: :pattern_matching,
      kind: :tuple_arity_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{pattern_arity: pattern_arity, expected: expected}
    }
  end

  def pattern_not_tuple(module, meta, got: got_type) do
    %Error{
      category: :pattern_matching,
      kind: :pattern_not_tuple,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_type}
    }
  end

  def complex_map_key(module, meta, key_ast) do
    %Error{
      category: :pattern_matching,
      kind: :complex_map_key,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{key_ast: key_ast}
    }
  end

  def invalid_map_key_type(module, meta, expected: expected, got: got) do
    %Error{
      category: :pattern_matching,
      kind: :invalid_map_key_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected: expected, got: got}
    }
  end

  def pattern_map_key_not_found(module, meta, missing_key) do
    %Error{
      category: :pattern_matching,
      kind: :pattern_map_key_not_found,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{missing_key: missing_key}
    }
  end

  def pattern_map_key_not_atom(module, meta, key_ast) do
    %Error{
      category: :pattern_matching,
      kind: :pattern_map_key_not_atom,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{key_ast: key_ast}
    }
  end
end
