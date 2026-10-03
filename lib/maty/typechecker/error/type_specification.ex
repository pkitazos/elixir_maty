defmodule Maty.Typechecker.Error.TypeSpecification do
  alias Maty.Typechecker.Error

  # external functions

  # MATY_ERROR_KIND_REVIEW
  # this isn't currently wired anywhere, but it's a real error
  # that should be invoked where session-type strings are parsed (in the pre-processor)
  #
  # the @st annotation string may fail to parse in which case we
  # should wrap the parse error we get from st_parser with some meta info
  def invalid_session_type_annotation(module, meta, handler_label, %Error.Cause{} = cause) do
    %Error{
      category: :type_specification,
      kind: :invalid_session_type_annotation,
      module: module,
      handler: handler_label,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{cause: cause}
    }
  end

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

  def unknown_type_constructor(type_name) do
    %Error.Cause{kind: :unknown_type_constructor, details: %{type: type_name}}
  end

  def heterogeneous_list_error(conflicting_types) do
    %Error.Cause{kind: :heterogeneous_list, details: %{types: conflicting_types}}
  end
end
