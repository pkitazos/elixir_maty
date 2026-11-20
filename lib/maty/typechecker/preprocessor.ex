defmodule Maty.Typechecker.Preprocessor do
  @moduledoc """
  Compile-time processing of a `Maty.Actor` module's state declarations.

  `process_state_declarations/2` checks the `global_state` / `local_state` declarations
  and parses their types. It runs once, at `@before_compile`, and returns the parsed
  types or the errors to the caller.

  `process_session_type_declarations/1` checks the `session_type` declarations
  and flattens them to the session type and role of each handler, also at `@before_compile`.
  """
  alias Maty.Typechecker.TypeSpecParser
  alias Maty.Typechecker.Error
  alias Maty.Types

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

  # `declarations` are the `@type` / `@typep` / `@opaque` attribute entries
  @spec process_type_declarations([tuple()]) :: result(TypeSpecParser.module_types())
  def process_type_declarations(declarations) do
    declarations =
      for {_kind, {:"::", _, [{name, meta, params}, body_ast]}, _location} <- declarations do
        # a type without parameters has `nil` for them
        {name, List.wrap(params), body_ast, meta[:line]}
      end
      |> Enum.sort_by(fn {_, _, _, line} -> line end)

    case TypeSpecParser.resolve_module_types(declarations) do
      {module_types, []} ->
        {:ok, module_types}

      {_module_types, problems} ->
        # todo: proper errors
        {:error,
         for {name, line, problem} <- problems do
           {:todo, "@type #{name} (line #{line}) does not resolve: #{inspect(problem)}"}
         end}
    end
  end

  # `roles` are the actor's roles, every one of them has a single `local_state`
  # `module_types` are the module's own types, from `process_type_declarations/1`
  @spec process_state_declarations(Macro.Env.t(), [Types.role()], TypeSpecParser.module_types()) ::
          {:ok, Types.state_types()} | {:error, [Error.t()]}
  def process_state_declarations(env, roles, module_types) do
    global_declarations = env.module |> Module.get_attribute(:global_state_type) |> Enum.reverse()
    local_declarations = env.module |> Module.get_attribute(:local_state_type) |> Enum.reverse()

    join(
      handle_global_declaration(env, global_declarations, module_types),
      handle_local_declarations(env, roles, local_declarations, module_types),
      fn g, l -> %{global: g, local: l} end
    )
  end

  @spec process_session_type_declarations(Macro.Env.t()) ::
          {:ok, %{Types.handler_label() => {Types.role(), ST.t()}}} | {:error, [Error.t()]}
  def process_session_type_declarations(env) do
    declarations = env.module |> Module.get_attribute(:session_type) |> Enum.reverse()

    # a role's later declarations are reported, and left out of the other checks
    {firsts, repeats} = split_repeated_roles(declarations)

    entries =
      for {role, handlers, line} <- firsts,
          {handler, st} <- handlers,
          do: {handler, role, st, line}

    duplicate_role_errors =
      for {role, _handlers, line} <- repeats,
          do: Error.FrameworkUsage.duplicate_role_session_type(env.module, [line: line], role)

    # within one declaration the macro already reported repeated handlers,
    # so a handler repeated here is named by two roles
    duplicate_handler_errors =
      for {handler, [_ | repeats]} <- Enum.group_by(entries, &elem(&1, 0)),
          {_handler, _role, _st, line} <- repeats,
          do:
            Error.FrameworkUsage.duplicate_handler_session_type(env.module, [line: line], handler)

    not_session_type_errors =
      for {_handler, _role, st, line} <- entries,
          not valid_session_type_start?(st),
          do:
            Error.FrameworkUsage.invalid_session_type_declaration(
              env.module,
              [line: line],
              :not_a_session_type,
              Macro.escape(st)
            )

    case duplicate_role_errors ++ duplicate_handler_errors ++ not_session_type_errors do
      [] -> {:ok, Map.new(entries, fn {handler, role, st, _line} -> {handler, {role, st}} end)}
      errors -> {:error, errors}
    end
  end

  defp split_repeated_roles(declarations) do
    firsts = Enum.uniq_by(declarations, &elem(&1, 0))
    {firsts, declarations -- firsts}
  end

  # a handler starts at the top of a session type, never at a branch
  defp valid_session_type_start?(%struct{}), do: struct in [ST.SIn, ST.SOut, ST.SName, ST.SEnd]
  defp valid_session_type_start?(_value), do: false

  defp handle_global_declaration(env, declarations, module_types) do
    case declarations do
      [{type_ast, line}] ->
        parse_state_type(env.module, :global, type_ast, line, module_types)

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

  defp handle_local_declarations(env, roles, declarations, module_types) do
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
           {:ok, type} <- parse_state_type(env.module, {:local, role}, ast, line, module_types) do
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

  defp parse_state_type(module, state, type_ast, line, module_types) do
    case TypeSpecParser.parse(type_ast, module_types) do
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
