defmodule Maty.Typechecker.PatternBinding do
  require Logger
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{Ctx, Error, Helpers}
  import Maty.Utils, only: [deftc: 2]

  @typedoc """
  Represents Elixir AST nodes that can be typechecked.
  """
  @type ast :: Macro.t()

  @typedoc """
  Environment mapping variable names to their types.
  Used to track types of variables during typechecking.
  """
  @type var_env() :: %{atom() => Type.t()}

  # move
  @doc """
  Checks if a pattern AST is compatible with an expected type and calculates
  the variable bindings introduced by the pattern. Corresponds to `⊢ p : A ⟹ Γ'`.

  Returns `{:ok, new_bindings, updated_env}` or `{:error, message, original_env}`.
  `new_bindings` contains only the variables bound in this pattern.
  `updated_env` is the original_env merged with new_bindings.
  """
  @spec tc_pattern(
          ctx :: Ctx.t(),
          pattern_ast :: ast(),
          expected_type :: Type.t(),
          var_env :: var_env()
        ) ::
          {:ok, map(), var_env()} | {:error, binary(), var_env()}

  # Pat-Var: Pattern is a variable 'x'
  deftc tc_pattern(_ctx, {var_name, _meta, context}, expected_type, var_env)
       when is_atom(var_name) and (is_atom(context) or is_nil(context)) do
    new_bindings = %{var_name => expected_type}
    updated_env = Map.merge(var_env, new_bindings)
    {:ok, new_bindings, updated_env}
  end

  # Pat-Wild: Pattern is '_'
  deftc tc_pattern(_ctx, :_, _expected_type, var_env) do
    {:ok, %{}, var_env}
  end

  deftc tc_pattern(
         _ctx,
         {:when, _,
          [
            {:x, _, Kernel},
            {{:., _, [:erlang, :orelse]}, _,
             [
               {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, false]},
               {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, nil]}
             ]}
          ]},
         _expected_type,
         var_env
       ) do
    {:ok, %{}, var_env}
  end

  deftc tc_pattern(_ctx, {:_, _meta, _context}, _expected_type, var_env) do
    {:ok, %{}, var_env}
  end

  # Pat-Value: Pattern is a literal value 'v'
  deftc tc_pattern(ctx, literal_pattern, expected_type, var_env)
       when is_number(literal_pattern) or
              is_binary(literal_pattern) or
              is_boolean(literal_pattern) or
              is_atom(literal_pattern) do
    case Helpers.get_literal_type(literal_pattern) do
      {:ok, literal_type} ->
        if literal_type == expected_type or literal_type == :atom do
          {:ok, %{}, var_env}
        else
          error =
            Error.PatternMatching.pattern_type_mismatch(ctx.module, ctx.meta,
              pattern: literal_pattern,
              expected: expected_type,
              got: literal_type
            )

          {:error, error, var_env}
        end

      :error ->
        error =
          Error.internal_error(
            ctx.meta,
            "Could not get type for literal pattern #{inspect(literal_pattern)}"
          )

        {:error, error, var_env}
    end
  end

  # Pat-EmptyList: Pattern is '[]'
  deftc tc_pattern(ctx, [], expected_type, var_env) do
    case expected_type do
      {:list, _} ->
        {:ok, %{}, var_env}

      :any ->
        {:ok, %{}, var_env}

      _ ->
        # todo: fix the `got` value
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, ctx.meta,
            pattern: [],
            expected: expected_type,
            got: "{:list, :any}"
          )

        {:error, error, var_env}
    end
  end

  # Pat-EmptyTuple: Pattern is '{}'
  deftc tc_pattern(ctx, {:{}, _, []}, expected_type, var_env) do
    case expected_type do
      {:tuple, []} ->
        {:ok, %{}, var_env}

      :any ->
        {:ok, %{}, var_env}

      _ ->
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, ctx.meta,
            pattern: {},
            expected: expected_type,
            got: "{:tuple, []}"
          )

        {:error, error, var_env}
    end
  end

  # Pat-EmptyMap: Pattern is '%{}'
  deftc tc_pattern(ctx, {:%{}, _, []}, expected_type, var_env) do
    case expected_type do
      {:map, _} ->
        {:ok, %{}, var_env}

      :any ->
        {:ok, %{}, var_env}

      _ ->
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, ctx.meta,
            pattern: %{},
            expected: expected_type,
            got: "{:map, %{}}"
          )

        {:error, error, var_env}
    end
  end

  # --- Recursive Pattern Clauses ---

  # Pat-Cons
  deftc tc_pattern(ctx, {:|, meta, [p1_ast, p2_ast]}, expected_type, var_env) do
    case expected_type do
      {:list, element_type} ->
        with {:p1, {:ok, bindings1, env1}} <-
               {:p1, tc_pattern(ctx, p1_ast, element_type, var_env)},
             {:p2, {:ok, bindings2, _env2}} <-
               {:p2, tc_pattern(ctx, p2_ast, expected_type, env1)},
             # pass env1 because env2 already contains bindings1
             # we only need to check bindings2 against bindings1
             {:merge, {:ok, merged_bindings, final_env}} <-
               {:merge,
                Helpers.check_and_merge_bindings(ctx.module, meta, bindings1, bindings2, env1)} do
          {:ok, merged_bindings, final_env}
        else
          {:p1, {:error, msg, env}} -> {:error, msg, env}
          {:p2, {:error, msg, env}} -> {:error, msg, env}
          {:merge, {:error, msg, env}} -> {:error, msg, env}
        end

      other_type ->
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, meta,
            pattern: "[h|t]",
            expected: "List",
            got: other_type
          )

        {:error, error, var_env}
    end
  end

  # Pat-Tuple
  deftc tc_pattern(ctx, {p1_ast, p2_ast} = pattern_ast, expected_type, var_env) do
    with {:type, {:tuple, [type_a, type_b]}} <- {:type, expected_type},
         {:p1, {:ok, bindings1, env1}} <- {:p1, tc_pattern(ctx, p1_ast, type_a, var_env)},
         {:p2, {:ok, bindings2, _env2}} <- {:p2, tc_pattern(ctx, p2_ast, type_b, env1)},
         meta = Helpers.extract_meta_from_pattern(pattern_ast),
         {:merge, {:ok, merged_bindings, final_env}} <-
           {:merge,
            Helpers.check_and_merge_bindings(ctx.module, meta, bindings1, bindings2, env1)} do
      {:ok, merged_bindings, final_env}
    else
      {:type, {:tuple, other_types}} ->
        meta = Helpers.extract_meta_from_pattern(pattern_ast)

        error =
          Error.PatternMatching.tuple_arity_mismatch(ctx.module, meta,
            pattern_arity: length(other_types),
            expected: 2
          )

        {:error, error, var_env}

      {:type, other_type} ->
        meta = Helpers.extract_meta_from_pattern(pattern_ast)

        error = Error.PatternMatching.pattern_not_tuple(ctx.module, meta, got: other_type)

        {:error, error, var_env}

      {:p1, {:error, msg, env}} ->
        {:error, msg, env}

      {:p2, {:error, msg, env}} ->
        {:error, msg, env}

      {:merge, {:error, msg, env}} ->
        {:error, msg, env}
    end
  end

  deftc tc_pattern(ctx, {:{}, meta, elements_asts}, expected_type, var_env) do
    case expected_type do
      {:tuple, expected_types} when length(elements_asts) == length(expected_types) ->
        # process elements sequentially, checking disjointedness at each step
        initial_acc = {:ok, %{}, var_env}

        Enum.zip(elements_asts, expected_types)
        |> Enum.reduce_while(
          initial_acc,
          fn {p_ast, p_expected_type}, {:ok, acc_bindings, current_env} ->
            case tc_pattern(ctx, p_ast, p_expected_type, current_env) do
              {:ok, new_bindings, updated_env} ->
                case Helpers.check_and_merge_bindings(
                       ctx.module,
                       meta,
                       acc_bindings,
                       new_bindings,
                       current_env
                     ) do
                  {:ok, merged_bindings, _env_ignored} ->
                    # use updated_env from the recursive call for the next iteration
                    {:cont, {:ok, merged_bindings, updated_env}}

                  {:error, msg, _env} ->
                    # halt on conflict
                    {:halt, {:error, msg, current_env}}
                end

              {:error, msg, _env} ->
                # halt if recursive call fails
                {:halt, {:error, msg, current_env}}
            end
          end
        )
        |> case do
          {:ok, final_bindings, final_env} -> {:ok, final_bindings, final_env}
          {:error, msg, env} -> {:error, msg, env}
        end

      {:tuple, expected_types} ->
        # todo: rethink this
        error =
          Error.PatternMatching.pattern_arity_mismatch(ctx.module, meta,
            pattern: "Tuple",
            expected: length(expected_types),
            got: length(elements_asts)
          )

        {:error, error, var_env}

      other_type ->
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, meta,
            pattern: "{...}",
            expected: "Tuple",
            got: other_type
          )

        {:error, error, var_env}
    end
  end

  # Pat-Map
  # Assuming keys k_i are literal atoms.
  deftc tc_pattern(ctx, {:%{}, meta, pairs}, expected_type, var_env) do
    case expected_type do
      {:map, expected_type_map} ->
        initial_acc = {:ok, %{}, var_env}

        Enum.reduce_while(
          pairs,
          initial_acc,
          fn {key_ast, p_ast}, {:ok, acc_bindings, current_env} ->
            literal_key = Helpers.ast_to_literal(key_ast)

            if not is_atom(literal_key) do
              {:halt,
               {:error, Error.PatternMatching.pattern_map_key_not_atom(ctx.module, meta, key_ast),
                current_env}}
            else
              # check if key exists in expected type map and get expected value type
              case Map.fetch(expected_type_map, literal_key) do
                {:ok, p_expected_type} ->
                  case tc_pattern(ctx, p_ast, p_expected_type, current_env) do
                    {:ok, new_bindings, updated_env} ->
                      # check disjointedness and merge
                      case Helpers.check_and_merge_bindings(
                             ctx.module,
                             meta,
                             acc_bindings,
                             new_bindings,
                             current_env
                           ) do
                        {:ok, merged_bindings, _env_ignored} ->
                          {:cont, {:ok, merged_bindings, updated_env}}

                        {:error, msg, _env} ->
                          {:halt, {:error, msg, current_env}}
                      end

                    {:error, msg, _env} ->
                      {:halt, {:error, msg, current_env}}
                  end

                :error ->
                  # key from pattern not found in expected map type
                  error =
                    Error.PatternMatching.pattern_map_key_not_found(ctx.module, meta, literal_key)

                  {:halt, {:error, error, current_env}}
              end
            end
          end
        )
        |> case do
          {:ok, final_bindings, final_env} -> {:ok, final_bindings, final_env}
          {:error, msg, env} -> {:error, msg, env}
        end

      other_type ->
        error =
          Error.PatternMatching.pattern_type_mismatch(ctx.module, meta,
            pattern: "%{...}",
            expected: "Map",
            got: other_type
          )

        {:error, error, var_env}
    end
  end
end
