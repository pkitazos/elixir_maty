defmodule Maty.Typechecker.TypeSpecParser do
  alias Maty.Typechecker.Error
  alias Maty.Types.T, as: Type

  @doc """
  Parses a restricted type specification AST into an internal type representation.

  Handles:
  - :atom, nil
  - {atom_name, _, []}  (looks up atom_name in type_env or treats as basic type)
  - {ast1, ast2}        (2-tuple)
  - {:{}, _, elements} (n-tuple)
  """
  @spec parse(type_ast :: Macro.t()) :: {:ok, Type.t()} | {:error, Error.Cause.t()}
  def parse(type_ast) do
    type_env =
      Maty.Types.payload_types()
      |> Enum.map(&{&1, &1})
      |> Enum.into(%{})
      |> Map.merge(Maty.Types.map())
      |> Map.put(:no_return, :no_return)
      |> Map.put(:any, :any)
      |> Map.put(:map, :map)

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
  defp do_parse({atom_name, _meta, []}, type_env) when is_atom(atom_name) do
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

  # Case 4: List {:list, _, [elements...]}
  defp do_parse({:list, _meta, elements_list}, type_env) when is_list(elements_list) do
    parse_list_elements(elements_list, type_env)
  end

  # Catch-all for unsupported AST formats
  defp do_parse(other_ast, _type_env) do
    error = Error.TypeSpecification.unsupported_type_constructor(other_ast)
    {:error, error}
  end

  defp parse_tuple_elements(element_asts, type_env) do
    element_asts
    |> Enum.reduce_while({:ok, []}, fn elem_ast, {:ok, acc} ->
      case do_parse(elem_ast, type_env) do
        {:ok, parsed_type} -> {:cont, {:ok, [parsed_type | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, types_reversed} -> {:ok, {:tuple, Enum.reverse(types_reversed)}}
      {:error, _} = err -> err
    end
  end

  defp parse_list_elements(element_asts, type_env) do
    element_asts
    |> Enum.reduce_while({:ok, []}, fn elem_ast, {:ok, acc} ->
      case do_parse(elem_ast, type_env) do
        {:ok, parsed_type} -> {:cont, {:ok, [parsed_type | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, types_reversed} ->
        all_types = types_reversed |> Enum.reverse() |> MapSet.new()

        if MapSet.size(all_types) == 1 do
          type = all_types |> MapSet.to_list() |> List.first()
          {:ok, {:list, type}}
        else
          error = Error.TypeSpecification.heterogeneous_list_error(MapSet.to_list(all_types))
          {:error, error}
        end

      {:error, _} = err ->
        err
    end
  end
end
