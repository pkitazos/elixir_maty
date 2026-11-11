defmodule Maty.Typechecker.Preprocessor do
  @moduledoc """
  Compile-time processing of a `Maty.Actor` module's state declarations.

  `process_state_declarations/1` checks the `global_state` / `local_state` declarations
  and parses their types. It runs once, at `@before_compile`, and returns the parsed
  types or the errors to the caller.
  """
  alias Maty.Typechecker.TypeSpecParser
  alias Maty.Typechecker.Error
  alias Maty.Types
  alias Maty.Types.T, as: Type

  @typep result(a) :: {:ok, a} | {:error, [Error.t()]}

  # as far as I can tell this is similar to `liftA2` in haskell
  @spec join(result(a), result(b), (a, b -> c)) :: result(c) when a: var, b: var, c: var
  defp join({:ok, a}, {:ok, b}, f), do: {:ok, f.(a, b)}
  defp join({:error, err}, {:ok, _}, _), do: {:error, err}
  defp join({:ok, _}, {:error, err}, _), do: {:error, err}
  defp join({:error, a}, {:error, b}, _), do: {:error, a ++ b}

  @spec map_m([a], (a -> result(b))) :: result([b]) when a: var, b: var
  defp map_m(xs, f) do
    {oks, errs} = xs |> Enum.map(f) |> Enum.split_with(&match?({:ok, _}, &1))

    case errs do
      [] -> {:ok, Enum.map(oks, fn {:ok, v} -> v end)}
      _ -> {:error, Enum.flat_map(errs, fn {:error, e} -> e end)}
    end
  end

  @spec process_state_declarations(Macro.Env.t()) ::
          {:ok, %{global: Type.t(), local: %{Types.role() => Type.t()}}} | {:error, [Error.t()]}
  def process_state_declarations(env) do
    roles = Module.get_attribute(env.module, :maty_roles)

    global_declarations = env.module |> Module.get_attribute(:global_state_type) |> Enum.reverse()
    local_declarations = env.module |> Module.get_attribute(:local_state_type) |> Enum.reverse()

    join(
      handle_global_declaration(env, global_declarations),
      handle_local_declarations(env, roles, local_declarations),
      fn g, l -> %{global: g, local: l} end
    )
  end

  defp handle_global_declaration(env, declarations) do
    case declarations do
      [{type_ast, line}] ->
        parse_state_type(env.module, :global, type_ast, line)

      [] ->
        error = Error.FrameworkUsage.missing_global_state(env.module, line: env.line)
        {:error, [error]}

      [_ | duplicates] ->
        errors =
          Enum.map(duplicates, fn {_, dup_line} ->
            Error.FrameworkUsage.duplicate_state_declaration(
              env.module,
              [line: dup_line],
              :global
            )
          end)

        {:error, errors}
    end
  end

  defp handle_local_declarations(env, roles, declarations) do
    declarations = Enum.group_by(declarations, fn {role, _ast, _line} -> role end)

    {under, over} = two_way_set_diff(roles, Map.keys(declarations))

    under_check =
      case under do
        [] ->
          {:ok, nil}

        _ ->
          {:error,
           [Error.FrameworkUsage.missing_local_states(env.module, [line: env.line], under)]}
      end

    over_check =
      map_m(over, fn role ->
        {:error,
         Enum.map(declarations[role], fn {_, _, line} ->
           Error.FrameworkUsage.local_state_undeclared_role(
             env.module,
             [line: line],
             role,
             roles
           )
         end)}
      end)

    declarations
    |> Map.take(roles)
    |> map_m(fn {role, role_declarations} ->
      with {:ok, {_role, ast, line}} <- check_in_role_duplicates(env, role, role_declarations),
           {:ok, type} <- parse_state_type(env.module, {:local, role}, ast, line) do
        {:ok, {role, type}}
      end
    end)
    |> join(under_check, fn types, _ -> Map.new(types) end)
    |> join(over_check, fn types, _ -> types end)
  end

  defp check_in_role_duplicates(env, role, role_declarations) do
    case role_declarations do
      [declaration] ->
        {:ok, declaration}

      [_ | duplicates] ->
        errors =
          Enum.map(duplicates, fn {_, _, dup_line} ->
            Error.FrameworkUsage.duplicate_state_declaration(
              env.module,
              [line: dup_line],
              {:local, role}
            )
          end)

        {:error, errors}
    end
  end

  defp two_way_set_diff(a, b) do
    a_minus_b = Enum.reject(a, &Enum.member?(b, &1))
    b_minus_a = Enum.reject(b, &Enum.member?(a, &1))

    {a_minus_b, b_minus_a}
  end

  defp parse_state_type(module, state, type_ast, line) do
    case TypeSpecParser.parse(type_ast) do
      {:ok, type} ->
        {:ok, type}

      {:error, cause} ->
        error =
          Error.TypeSpecification.state_type_not_well_typed(
            module,
            [line: line],
            state,
            type_ast,
            cause
          )

        {:error, [error]}
    end
  end
end
