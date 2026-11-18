defmodule Maty.Typechecker.TypeSpecParser do
  alias Maty.Typechecker.Error
  alias Maty.Types.T, as: Type
  import Maty.Types, only: [is_label: 1]

  @doc """
  Parses a restricted type specification AST into an internal type representation.

  Handles:
  - :atom, nil
  - {atom_name, _, []}  (looks up atom_name in type_env or treats as basic type)
  - {ast1, ast2}        (2-tuple)
  - {:{}, _, elements} (n-tuple)
  - {:%{}, _, fields}  (map record with literal atom keys, e.g. %{name: binary()})
  - {:%{}, _, [{k, v}]} (map dictionary with a base key type, e.g. %{atom() => binary()})
  - [{:->, _, [args, ret]}] (function, e.g. (number(), atom() -> binary()))
  - [t]                (list, the same as list(t))
  """
  @spec parse(type_ast :: Macro.t()) :: {:ok, Type.t()} | {:error, Error.Cause.t()}
  def parse(type_ast) do
    # todo: this should probably be build in `Types`
    type_env =
      Maty.Types.payload_types()
      |> Map.new(fn x -> {x, x} end)
      |> Map.put(:no_return, :no_return)

    parse(type_ast, type_env)
  end

  defp parse(type_ast, type_env) do
    do_parse(type_ast, type_env)
  end

  # Base Case: Literal nil
  defp do_parse(nil, _type_env), do: {:ok, nil}

  # Date Type constructor
  defp do_parse({{:., _, [{:__aliases__, _, [:Date]}, :t]}, _, []}, _type_env), do: {:ok, :date}

  # Base Case: Literal Atom (e.g., :ok, :error, :atom)
  defp do_parse(atom_name, _type_env) when is_atom(atom_name) do
    {:ok, atom_name}
  end

  # Case 1: Zero-arity Type Constructor {name, _, []}
  # (`%{}` has the same shape, it is handled by the map record case below)
  defp do_parse({atom_name, _meta, []}, type_env) when is_atom(atom_name) and atom_name != :%{} do
    case Map.fetch(type_env, atom_name) do
      {:ok, internal_type} ->
        {:ok, internal_type}

      :error ->
        error = Error.TypeSpecification.unknown_type_constructor(atom_name)
        {:error, error}
    end
  end

  # Case 2: 2-Tuple {ast1, ast2}
  defp do_parse({ast1, ast2}, type_env) when is_tuple(ast1) or is_atom(ast1) do
    parse_tuple_elements([ast1, ast2], type_env)
  end

  # Case 3: N-Tuple {:{}, _, [elements...]}
  defp do_parse({:{}, _meta, elements_list}, type_env) when is_list(elements_list) do
    parse_tuple_elements(elements_list, type_env)
  end

  # Case 4: List list(t)
  # (`list/1` is the only list constructor, `list()` and `list(a, b)` are not supported)
  defp do_parse({:list, _meta, [elem_ast]}, type_env) do
    with {:ok, elem_type} <- do_parse(elem_ast, type_env) do
      {:ok, {:list, elem_type}}
    end
  end

  # `%{}` is not a type: a record has at least one field, and a dictionary names its key and value types
  defp do_parse({:%{}, _meta, []} = map_ast, _type_env) do
    {:error, Error.TypeSpecification.empty_record(map_ast)}
  end

  # Case 6: Map dictionary %{k => v}
  # a single entry whose key is a type rather than a literal atom, the key type must be a base type
  defp do_parse({:%{}, _meta, [{key_ast, value_ast}]} = map_ast, type_env)
       when not is_atom(key_ast) do
    with {:ok, key_type} <- do_parse(key_ast, type_env),
         {:base, true, _key_type} <- {:base, Maty.Types.is_base_type?(key_type), key_type},
         {:ok, value_type} <- do_parse(value_ast, type_env) do
      {:ok, {:map_dict, {key_type, value_type}}}
    else
      {:base, false, key_type} ->
        {:error, Error.TypeSpecification.dict_key_not_base_type(map_ast, key_type)}

      {:error, _} = err ->
        err
    end
  end

  # Case 5: Map record %{k1: t1, ...}
  # only valid label keys, each at most once (`true`, `false` and `nil` are atoms but not considered labels)
  # `required(...)`/`optional(...)` and other keys are not supported
  defp do_parse({:%{}, _meta, fields} = map_ast, type_env) when is_list(fields) do
    not_labels = for {key, _type_ast} <- fields, is_atom(key) and not is_label(key), do: key
    atom_keyed? = Enum.all?(fields, &match?({key, _type_ast} when is_label(key), &1))

    cond do
      not_labels != [] ->
        error = Error.TypeSpecification.invalid_record_label(map_ast, hd(not_labels))
        {:error, error}

      atom_keyed? and length(Enum.uniq_by(fields, fn {k, _} -> k end)) == length(fields) ->
        parse_map_record_fields(fields, type_env)

      true ->
        error = Error.TypeSpecification.unsupported_type_constructor(map_ast)
        {:error, error}
    end
  end

  # Case 7: Function (t1, ..., tn -> t)
  # the parentheses make it a one-element list holding the arrow
  # (`(a -> b; c -> d)` has several arrows and is not supported)
  defp do_parse([{:->, _meta, [arg_asts, return_ast]}], type_env) when is_list(arg_asts) do
    with {:ok, arg_types} <- parse_all(arg_asts, type_env),
         {:ok, return_type} <- do_parse(return_ast, type_env) do
      {:ok, {:function, arg_types, return_type}}
    end
  end

  # Case 8: List [t]
  # must come after the function case, whose `[{:->, _, _}]` also has one element
  # (`[]`, `[t, ...]` and lists of several types fall through to the catch-all)
  defp do_parse([elem_ast], type_env) do
    with {:ok, elem_type} <- do_parse(elem_ast, type_env) do
      {:ok, {:list, elem_type}}
    end
  end

  # Catch-all for unsupported AST formats
  defp do_parse(other_ast, _type_env) do
    error = Error.TypeSpecification.unsupported_type_constructor(other_ast)
    {:error, error}
  end

  # parses each type in order, stopping at the first that fails
  defp parse_all(asts, type_env) do
    asts
    |> Enum.reduce_while({:ok, []}, fn ast, {:ok, acc} ->
      case do_parse(ast, type_env) do
        {:ok, parsed_type} -> {:cont, {:ok, [parsed_type | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, types_reversed} -> {:ok, Enum.reverse(types_reversed)}
      {:error, _} = err -> err
    end
  end

  defp parse_tuple_elements(element_asts, type_env) do
    with {:ok, types} <- parse_all(element_asts, type_env) do
      {:ok, {:tuple, types}}
    end
  end

  defp parse_map_record_fields(fields, type_env) do
    fields
    |> Enum.reduce_while({:ok, []}, fn {key, type_ast}, {:ok, acc} ->
      case do_parse(type_ast, type_env) do
        {:ok, parsed_type} -> {:cont, {:ok, [{key, parsed_type} | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, parsed_fields} -> {:ok, {:map_record, Map.new(parsed_fields)}}
      {:error, _} = err -> err
    end
  end
end
