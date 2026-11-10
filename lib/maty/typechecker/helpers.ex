defmodule Maty.Typechecker.Helpers do
  require Logger

  alias Maty.ST.SBottom
  alias Maty.Typechecker.Error
  alias Maty.Types.T, as: Type

  @arith_ops [:+, :-, :*, :/]
  @ord_ops [:<, :>, :<=, :>=]
  @log_ops [:and, :or]
  @eq_ops [:==, :!=]

  @doc """
  Checks if the types of operands are valid for the given binary operator
  and returns the result type, based on the OpTypeRel formal rule.

  Returns `{:ok, result_type}` or `:error`.
  """
  @spec op_type_rel(atom(), a, a) :: {:ok, a} | :error when a: Type.t()
  def op_type_rel(op, :number, :number) when op in @arith_ops, do: {:ok, :number}
  def op_type_rel(op, _, _) when op in @arith_ops, do: :error

  def op_type_rel(op, :number, :number) when op in @ord_ops, do: {:ok, :boolean}
  def op_type_rel(op, _, _) when op in @ord_ops, do: :error

  def op_type_rel(op, :boolean, :boolean) when op in @log_ops, do: {:ok, :boolean}
  def op_type_rel(op, _, _) when op in @log_ops, do: :error

  def op_type_rel(op, a, b) when op in @eq_ops and a == b, do: {:ok, :boolean}
  def op_type_rel(op, _, _) when op in @eq_ops, do: :error

  def op_type_rel(:<>, :binary, :binary), do: {:ok, :binary}
  def op_type_rel(:<>, _, _), do: :error

  # Catch-all for any operators not defined above
  def op_type_rel(_op, _a, _b), do: :error

  # pattern binding helpers

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
          {:ok, map(), map()} | {:error, Error.t(), map()}
  def check_and_merge_bindings(module, meta, bindings1, bindings2, current_env) do
    keys1 = Map.keys(bindings1) |> MapSet.new()
    keys2 = Map.keys(bindings2) |> MapSet.new()

    intersection = MapSet.intersection(keys1, keys2)

    if MapSet.size(intersection) == 0 do
      merged_new_bindings = Map.merge(bindings1, bindings2)
      updated_env = Map.merge(current_env, merged_new_bindings)
      {:ok, merged_new_bindings, updated_env}
    else
      conflicting_vars = intersection |> MapSet.to_list() |> Enum.sort()
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

  # end of pattern binding helpers

  @doc """
  Joins two types according to the lattice rules (T ⊔ T = T, ⊥ ⊔ T = T).
  Uses :no_return to represent the bottom type ⊥_T.
  Returns the joined type or :error if they cannot be joined.
  """
  @spec join_types(Type.t(), Type.t()) :: Type.t() | :error
  def join_types(:no_return, rhs), do: rhs
  def join_types(lhs, :no_return), do: lhs
  def join_types(lhs, rhs) when lhs == rhs, do: lhs
  # todo: potentially add rules for compatible types? (e.g., integer/number -> number)
  # For now, require exact match or bottom.
  def join_types(_lhs, _rhs), do: :error

  @doc """
  Joins two session types according to the lattice rules (Q ⊔ Q = Q, ⊥ ⊔ Q = Q).
  Uses %SBottom{} to represent the bottom type ⊥_S.
  Returns the joined type or :error if they cannot be joined.
  """
  @spec join_session_types(ST.t() | atom, ST.t() | atom) :: ST.t() | :error
  def join_session_types(%SBottom{}, rhs), do: rhs
  def join_session_types(lhs, %SBottom{}), do: lhs
  def join_session_types(lhs, rhs) when lhs == rhs, do: lhs
  def join_session_types(_lhs, _rhs), do: :error

  def join_branch_results([]) do
    {:ok, {:no_return, %SBottom{reason: :nothing}}}
  end

  def join_branch_results([{t, q} | rest_results]) do
    # fold over results, joining pairwise
    Enum.reduce_while(rest_results, {:ok, {t, q}}, fn {ti, qi}, {:ok, {acc_t, acc_q}} ->
      joined_t = join_types(acc_t, ti)
      joined_q = join_session_types(acc_q, qi)

      type_ok? = joined_t != :error
      session_ok? = joined_q != :error

      if type_ok? and session_ok? do
        {:cont, {:ok, {joined_t, joined_q}}}
      else
        # collect every join that failed at this step so the reporting site can
        # surface an incompatible type pair AND an incompatible session-state pair
        type_branches = if type_ok?, do: [], else: [t1: acc_t, t2: ti]
        session_branches = if session_ok?, do: [], else: [q1: acc_q, q2: qi]

        {:halt, {:error, type_branches ++ session_branches}}
      end
    end)
  end

  def try_get_matching_branch(branches, label, payload_type) do
    case Enum.find(branches, &(&1.label == label)) do
      %ST.SBranch{payload: ^payload_type} = b -> {:ok, b}
      %ST.SBranch{} = b -> {:error, :payload_mismatch, b}
      nil -> {:error, :label_mismatch}
    end
  end

  @doc """
  The possible types an init handler can accept based on its clauses

  `handler_name` is looked up in Δ_I to get the init handler's function id.
  That id is then looked up in Ψ to get its signatures.
  Each signature is `{arg_types, :no_return}` where `arg_types` is `[args, state, session_ctx]`,
  so only the first element is kept.

  Returns `:error` when `handler_name` is not an init handler of the module, and
  `{:ok, []}` when it is but has no spec.
  """
  # todo: register accepts args that fit any clause's spec
  # but at runtime the first clause whose pattern matches runs
  # (see the todo in T-App (tc.ex) for the same issue with function calls)
  def init_handler_arg_types(ctx, handler_name) do
    with {:ok, %{function: func_id}} <- Map.fetch(ctx.delta_I, handler_name) do
      # a missing psi entry is reported as a missing spec on the handler itself
      arg_types =
        ctx.psi
        |> Map.get(func_id, [])
        |> Enum.map(fn {:function, [arg | _], _} -> arg end)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, arg_types}
    end
  end

  # todo: move somewhere else?
  @spec contains_register_call?(Macro.t()) :: boolean()
  def contains_register_call?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [Maty.Runtime, :register]}, _meta, _args} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
