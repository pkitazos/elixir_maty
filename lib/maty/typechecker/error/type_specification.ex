defmodule Maty.Typechecker.Error.TypeSpecification do
  alias Maty.Typechecker.Error

  # external functions

  def spec_return_not_well_typed(
        module,
        meta,
        spec_name,
        return_ast,
        %Error.Cause{} = cause
      ) do
    %Error{
      category: :type_specification,
      kind: :spec_return_not_well_typed,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{spec_name: spec_name, return_ast: return_ast, cause: cause}
    }
  end

  # the type given to `global_state` / `local_state` does not parse
  # `state` is `:global` or `{:local, role}`
  def state_type_not_well_typed(module, meta, state, type_ast, %Error.Cause{} = cause) do
    %Error{
      category: :type_specification,
      kind: :state_type_not_well_typed,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{state: state, type_ast: type_ast, cause: cause}
    }
  end

  # one of the module types (`@type` / `@typep` / `@opaque`) does not resolve
  def module_type_not_well_typed(module, meta, name, %Error.Cause{} = cause) do
    %Error{
      category: :type_specification,
      kind: :module_type_not_well_typed,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{name: name, cause: cause}
    }
  end

  def spec_args_parse_error_at(
        module,
        meta,
        func_id,
        failed_index,
        args_asts,
        %Error.Cause{} = cause
      ) do
    %Error{
      category: :type_specification,
      kind: :spec_args_parse_error_at,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{
        func_id: func_id,
        failed_index: failed_index,
        args_asts: args_asts,
        cause: cause
      }
    }
  end

  def function_spec_info_mismatch(module, meta, spec_id: spec_id, func_id: func_id) do
    %Error{
      category: :type_specification,
      kind: :function_spec_info_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{spec_id: spec_id, func_id: func_id}
    }
  end

  def no_spec_for_function(module, meta, func_id) do
    %Error{
      category: :type_specification,
      kind: :no_spec_for_function,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{func_id: func_id}
    }
  end

  # causes: payloads embedded in other errors under `details.cause`

  def unsupported_type_constructor(type_ast) do
    %Error.Cause{kind: :unsupported_type_constructor, details: %{type_ast: type_ast}}
  end

  # a record type uses `true`, `false` or `nil` as a label: they are atoms, but the constants of Bool and Nil
  def invalid_record_label(type_ast, label) do
    %Error.Cause{kind: :invalid_record_label, details: %{type_ast: type_ast, label: label}}
  end

  def unknown_type_constructor(type_name) do
    %Error.Cause{kind: :unknown_type_constructor, details: %{type: type_name}}
  end

  # a record type with no fields, `%{}`: a record has at least one
  def empty_record(type_ast) do
    %Error.Cause{kind: :empty_record, details: %{type_ast: type_ast}}
  end

  # a dictionary type `%{k => v}` whose key type is not a base type
  def dict_key_not_base_type(type_ast, key_type) do
    %Error.Cause{
      kind: :dict_key_not_base_type,
      details: %{type_ast: type_ast, key_type: key_type}
    }
  end

  # a module type that is still being resolved uses `through`, so it uses itself
  def recursive_type(through) do
    %Error.Cause{kind: :recursive_type, details: %{through: through}}
  end

  # a module type with parameters, `@type name(a, ...) :: ...`
  def parametric_type(name, arity) do
    %Error.Cause{kind: :parametric_type, details: %{name: name, arity: arity}}
  end

  # a type from another module, `Mod.t()`
  def remote_type(type_ast) do
    %Error.Cause{kind: :remote_type, details: %{type_ast: type_ast}}
  end
end
