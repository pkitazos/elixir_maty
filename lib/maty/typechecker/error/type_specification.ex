defmodule Maty.Typechecker.Error.TypeSpecification do
  alias Maty.Typechecker.Error

  # external functions
  def invalid_session_type_annotation(module, meta, handler_label, %Error.Internal{
        title: title,
        opts: opts,
        message: message
      }) do
    line = Keyword.fetch!(meta, :line)

    """
    \n\n** (ElixirMatyTypeError) Type Specification Error: Invalid Session Type Annotation
      Module: #{module}
      Line: #{line}
      --
      Handler: #{handler_label}
      Parse error: #{title}
      #{opts}
      --
      The @st annotation contains an invalid session type string that cannot be parsed.

      Details: #{message}
    """
  end

  def spec_return_not_well_typed(module, meta, spec_name, return_ast, %Error.Internal{} = internal) do
    %Error{
      category: :type_specification,
      kind: :spec_return_not_well_typed,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{spec_name: spec_name, return_ast: return_ast, internal: internal}
    }
  end

  def spec_args_parse_error_at(module, meta, func_id, failed_index, args_asts, %Error.Internal{} = internal) do
    %Error{
      category: :type_specification,
      kind: :spec_args_parse_error_at,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{
        func_id: func_id,
        failed_index: failed_index,
        args_asts: args_asts,
        internal: internal
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

  def no_spec_for_function(module, func_id) do
    %Error{
      category: :type_specification,
      kind: :no_spec_for_function,
      module: module,
      details: %{func_id: func_id}
    }
  end

  # internal functions

  def unsupported_type_constructor(type_ast) do
    %Error.Internal{
      title: "Unsupported Type Constructor",
      opts: "Type AST: #{inspect(type_ast)}",
      message: "This type specification AST structure is not supported by the typechecker."
    }
  end

  def unknown_type_constructor(type_name) do
    %Error.Internal{
      title: "Unknown Type Constructor",
      opts: "Type: #{type_name}",
      message: "Unknown type constructor or type atom not found in the type environment."
    }
  end

  def heterogeneous_list_error(conflicting_types) do
    formatted_types =
      conflicting_types
      |> Enum.map(&inspect/1)
      |> Enum.join(", ")

    %Error.Internal{
      title: "Heterogeneous List Type",
      opts: "Conflicting types found: #{formatted_types}",
      message: "List type specifications must contain elements of the same type."
    }
  end
end
