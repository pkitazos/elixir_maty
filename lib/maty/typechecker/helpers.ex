defmodule Maty.Typechecker.Helpers do
  require Logger

  alias Maty.ST.SBottom
  alias Maty.Typechecker.Error
  alias Maty.Types.T, as: Type

  # Helper to unify list element types (simple version)
  # Returns unified type or :error_incompatible
  def unify_list_types([]) do
    # Type of empty list element is any/nil
    {:ok, :any}
  end

  def unify_list_types([type | rest]) do
    if Enum.all?(rest, &(&1 == type)) do
      {:ok, type}
    else
      {:error, :incompatible}
    end
  end

  def unify_list_types(type) when not is_list(type), do: {:error, :incompatible}

  # Helper to check if a type is a valid base type for map keys (Formal C)
  def is_base_type?(:atom), do: true
  def is_base_type?(nil), do: true
  def is_base_type?(:boolean), do: true
  def is_base_type?(:number), do: true
  def is_base_type?(:binary), do: true
  def is_base_type?(:date), do: true
  def is_base_type?(:pid), do: true
  def is_base_type?(:ref), do: true
  # Add other base types if necessary (e.g., from Maty.Types)
  def is_base_type?(_other), do: false

  @doc """
  Checks if the types of operands are valid for the given binary operator
  and returns the result type, based on the OpTypeRel formal rule.

  Returns `{:ok, result_type}` or `:error`.
  """
  @spec op_type_rel(op :: atom(), type_a :: Type.t(), type_b :: Type.t()) ::
          {:ok, Type.t()} | :error
  def op_type_rel(op, a, b) when op in [:+, :-, :*, :/] do
    if a == :number and b == :number, do: {:ok, :number}, else: :error
  end

  def op_type_rel(:<>, a, b) do
    if a == :binary and b == :binary, do: {:ok, :binary}, else: :error
  end

  def op_type_rel(op, a, b) when op in [:and, :or] do
    if a == :boolean and b == :boolean, do: {:ok, :boolean}, else: :error
  end

  def op_type_rel(op, a, b) when op in [:<, :>, :<=, :>=] do
    if a == :number and b == :number, do: {:ok, :boolean}, else: :error
  end

  def op_type_rel(op, a, b) when op in [:==, :!=] do
    # Formal rule requires A = B.
    # Simple equality check sufficient for base types.
    if a == b, do: {:ok, :boolean}, else: :error
  end

  # Catch-all for any operators not defined above
  def op_type_rel(_op, _a, _b), do: :error

  @doc """
  Attempts to convert simple AST nodes representing literals into their
  actual literal values. Used primarily for map keys.

  Returns the literal value on success, or :error_complex_key for nodes
  that don't represent a simple literal.
  """
  @spec ast_to_literal(ast :: Macro.t()) :: {:ok, term()} | :error
  # Atom literal: AST is typically {atom_value, meta, context_atom_or_nil}
  def ast_to_literal({atom_value, _meta, _context}) when is_atom(atom_value) do
    {:ok, atom_value}
  end

  # Other literals (numbers, binaries, booleans, nil) often appear directly in AST
  def ast_to_literal(literal) when is_number(literal), do: {:ok, literal}
  def ast_to_literal(literal) when is_binary(literal), do: {:ok, literal}
  def ast_to_literal(literal) when is_boolean(literal), do: {:ok, literal}
  def ast_to_literal(nil), do: {:ok, nil}
  def ast_to_literal(literal) when is_atom(literal), do: {:ok, literal}

  # If the AST node doesn't match a simple literal form
  def ast_to_literal(_other_ast), do: :error

  def get_literal_type(nil), do: {:ok, nil}
  def get_literal_type(literal) when is_boolean(literal), do: {:ok, :boolean}
  def get_literal_type(literal) when is_number(literal), do: {:ok, :number}
  def get_literal_type(literal) when is_binary(literal), do: {:ok, :binary}
  def get_literal_type(literal) when is_atom(literal), do: {:ok, :atom}

  # Not a recognised simple literal
  def get_literal_type(_), do: :error

  @doc """
  Merges two maps of new variable bindings, checking for conflicting keys.
  If successful, returns the merged new bindings and the fully updated env.
  """
  @spec check_and_merge_bindings(
          module :: module(),
          meta :: Keyword.t(),
          bindings1 :: map(),
          bindings2 :: map(),
          current_env :: map()
        ) ::
          {:ok, map(), map()} | {:error, String.t(), map()}
  def check_and_merge_bindings(module, meta, bindings1, bindings2, current_env) do
    keys1 = Map.keys(bindings1) |> MapSet.new()
    keys2 = Map.keys(bindings2) |> MapSet.new()

    intersection = MapSet.intersection(keys1, keys2)

    if MapSet.size(intersection) == 0 do
      merged_new_bindings = Map.merge(bindings1, bindings2)
      updated_env = Map.merge(current_env, merged_new_bindings)
      {:ok, merged_new_bindings, updated_env}
    else
      conflicting_vars = Enum.join(intersection, ", ")
      error = Error.PatternMatching.conflicting_pattern_bindings(module, meta, conflicting_vars)
      {:error, error, current_env}
    end
  end

  @spec extract_meta_from_pattern({Macro.t(), Macro.t()}) :: Keyword.t()
  def extract_meta_from_pattern({p1_ast, p2_ast}) do
    case extract_meta_from_ast(p1_ast) do
      [] -> extract_meta_from_ast(p2_ast)
      meta -> meta
    end
  end

  def extract_meta_from_ast({_var, meta, _context}) when is_list(meta), do: meta
  def extract_meta_from_ast({_var, _meta, _context}), do: []
  def extract_meta_from_ast(_), do: []

  @doc """
  Joins two types according to the lattice rules (T ⊔ T = T, ⊥ ⊔ T = T).
  Uses :no_return to represent the bottom type ⊥_T.
  Returns the joined type or :error_incompatible_types if they cannot be joined.
  """
  @spec join_types(type1 :: Type.t(), type2 :: Type.t()) :: Type.t() | :error_incompatible_types
  def join_types(:no_return, type2), do: type2
  def join_types(type1, :no_return), do: type1
  def join_types(type1, type2) when type1 == type2, do: type1
  # todo: add rules for compatible types? (e.g., integer/number -> number)
  # For now, require exact match or bottom.
  def join_types(_type1, _type2), do: :error_incompatible_types

  @doc """
  Joins two session types according to the lattice rules (Q ⊔ Q = Q, ⊥ ⊔ Q = Q).
  Uses %SBottom{} to represent the bottom type ⊥_S.
  Returns the joined type or :error_incompatible_session_types if they cannot be joined.
  """
  # @spec join_session_types(st1 :: ST.t() | atom, st2 :: ST.t() | atom) :: ST.t() | atom
  def join_session_types(%SBottom{}, st2), do: st2
  def join_session_types(st1, %SBottom{}), do: st1
  # Use structural comparison for session types
  def join_session_types(st1, st2) when st1 == st2, do: st1
  # todo: any other join rules? (e.g., joining identical choices) - unlikely needed for now.
  def join_session_types(_st1, _st2), do: :error_incompatible_session_types

  def check_st_unchanged(st_pre, st_post, meta) do
    if st_pre == st_post do
      :ok
    else
      {:error, Error.case_scrutinee_altered_state(meta, from: st_pre, to: st_post)}
    end
  end

  def join_branch_results([]) do
    {:ok, {:no_return, %SBottom{reason: :nothing}}}
  end

  def join_branch_results([{t, q} | rest_results]) do
    # fold over results, joining pairwise
    Enum.reduce_while(rest_results, {:ok, {t, q}}, fn {ti, qi}, {:ok, {acc_t, acc_q}} ->
      joined_t = join_types(acc_t, ti)
      joined_q = join_session_types(acc_q, qi)

      if joined_t != :error_incompatible_types and joined_q != :error_incompatible_session_types do
        {:cont, {:ok, {joined_t, joined_q}}}
      else
        # determine which join failed
        error_branches =
          if joined_t == :error_incompatible_types do
            [t1: acc_t, t2: ti]
          else
            [q1: acc_q, q2: qi]
          end

        {:halt, {:error, error_branches}}
      end
    end)
  end

  def check_message_structure(_ctx, _meta, {label_atom, payload_expr_ast})
      when is_atom(label_atom) do
    {:ok, {label_atom, payload_expr_ast}}
  end

  def check_message_structure(ctx, meta, other_ast) do
    error = Error.TypeMismatch.send_message_not_tuple(ctx.module, meta, got: other_ast)
    {:error, error}
  end

  def find_matching_branch(branches, {label, payload_type}) do
    branches
    |> Enum.map(fn %ST.SBranch{label: l, payload: p} = branch ->
      cond do
        l == label and p == payload_type -> {:ok, branch}
        l != label -> {:error, :label_mismatch}
        true -> {:error, :payload_mismatch}
      end
    end)
    |> then(fn bs -> Enum.find(bs, bs, &match?({:ok, _}, &1)) end)
    |> case do
      {:ok, matched_branch} -> {:ok, matched_branch}
      [error | _] -> error
    end

    # if Enum.any?(bs, &match?({:ok, _}, &1)) do
    #   Enum.find()
    # end

    # Enum.find(
    #   branches,
    #   fn %ST.SBranch{label: l, payload: p} ->
    #     l == label and p == payload_type
    #   end
    # )
    # |> case do
    #   nil -> {:error, :payload_mismatch}
    #   matched_branch -> {:ok, matched_branch}
    # end
  end

  # Checks if a type is one of the valid handler types we defined earlier
  def check_handler_type(:maty_handler_msg), do: :ok
  def check_handler_type(:maty_handler_init), do: :ok
  def check_handler_type(_other_type), do: {:error, :not_a_handler}

  # Checks if a type is compatible with maty_actor_state
  def check_maty_state_type(state_type) do
    if Type.is?(state_type, :maty_actor_state) do
      {:ok, Type.maty_actor_state()}
    else
      {:error, Error.TypeMismatch.invalid_maty_state_type(state_type)}
    end
  end

  def extract_capture_fun_id({:&, _, [{:/, _, [{{:., _, [_mod, fun]}, _, _}, arity]}]})
      when is_atom(fun) and is_integer(arity),
      do: {:ok, {fun, arity}}

  def extract_capture_fun_id({:&, _, [{:/, _, [fun, arity]}]})
      when is_atom(fun) and is_integer(arity),
      do: {:ok, {fun, arity}}

  def extract_capture_fun_id(_other_ast), do: :error

  @spec contains_register_call?(Macro.t()) :: boolean()

  def contains_register_call?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [Maty.DSL, :register]}, _meta, _args} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
