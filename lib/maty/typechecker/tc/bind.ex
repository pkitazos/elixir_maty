defmodule Maty.Typechecker.TC.Bind do
  @moduledoc """
  Threading combinators for the typechecker.

  Every `tc_expr/4` clause implements the judgement

      Ψ; Δ; Γ | Q₁ ⊳ e : T ⊲ Q₂

  which is really a state computation: it reads/updates the variable
  environment Γ (`var_env`) and advances the session type from Q₁ (`st_pre`)
  to Q₂, while producing a type `T`.
  The success/failure shape is the one the typechecker already uses:

      {:ok, {value, st}, env}      # value :: Type.t(), st :: Maty.ST.t(), env :: var_env()
      {:error, reason, env}

  These helpers thread `env` and `st` so individual clauses stop passing them
  around by hand. `bind/2` takes a continuation that receives the unpacked `(value, env, st)`,
  so the "which env/st do I pass next" decision can go away
  and so can the `{:v1, ...}` / `{:e1, ...}` disambiguation tags in the `with` blocks.
  """

  alias Maty.Typechecker.{Error, Judgment}

  @type var_env :: Judgment.var_env()
  @type result(a) :: Judgment.result(a)
  @type t(a) :: result(a)

  @doc "Lift a value into a successful result, leaving env and st untouched (pure / return)."
  @spec ok(a, var_env(), Maty.ST.t()) :: t(a) when a: var
  def ok(value, env, st), do: {:ok, value, st, env}

  @doc "Build a failure carrying the current env."
  @spec error(term(), var_env()) :: {:error, term(), var_env()}
  def error(reason, env), do: {:error, reason, env}

  @doc """
  Sequence two steps. On success, calls `fun.(value, env, st)` with the
  unpacked result of the first step; on failure, short-circuits. `fun` must
  return a `t()`.
  """
  @spec bind(t(a), (a, var_env(), Maty.ST.t() -> t(b))) :: t(b) when a: var, b: var
  def bind({:ok, value, st, env}, fun), do: fun.(value, env, st)
  def bind({:error, _, _} = err, _fun), do: err

  @doc "Transform the produced value, leaving env and st untouched."
  @spec map(t(a), (a -> b)) :: t(b) when a: var, b: var
  def map(result, fun), do: bind(result, fn v, env, st -> ok(fun.(v), env, st) end)

  @doc """
  Thread `env` and `st` left-to-right across `items`, applying
  `fun.(item, env, st)` to each and collecting the produced values in order.
  Short-circuits on the first error (returning it with the env at that point).
  """
  @spec traverse([a], var_env(), Maty.ST.t(), (a, var_env(), Maty.ST.t() -> t(b))) :: t([b])
        when a: var, b: var
  def traverse(items, env, st, fun) do
    items
    |> Enum.reduce_while({:ok, [], st, env}, fn item, {:ok, acc, cur_st, cur_env} ->
      case fun.(item, cur_env, cur_st) do
        {:ok, value, next_st, next_env} ->
          {:cont, {:ok, [value | acc], next_st, next_env}}

        {:error, _reason, _env} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, rev, final_st, final_env} -> {:ok, Enum.reverse(rev), final_st, final_env}
      {:error, _reason, _env} = err -> err
    end
  end

  def fan_out(items, env, st, fun) do
    results = Enum.map(items, fn item -> fun.(item, env, st) end)

    case Enum.find(results, &match?({:error, _, _}, &1)) do
      {:error, msg, _err_env} ->
        error(msg, env)

      nil ->
        values = Enum.map(results, fn {:ok, val, branch_st, _env} -> {val, branch_st} end)
        ok(values, env, st)
    end
  end

  @spec lift_result({:ok, a} | {:error, term()}, term(), var_env(), Maty.ST.t()) :: result(a)
        when a: var
  def lift_result({:error, _reason}, error, env, _st), do: error(error, env)
  def lift_result(:error, error, env, _st), do: error(error, env)
  def lift_result({:ok, val}, _error, env, st), do: ok(val, env, st)

  @doc "Like lift_result/4 but preserves the original error reason."
  @spec lift_result({:ok, a} | {:error, term()}, var_env(), Maty.ST.t()) :: result(a)
        when a: var
  def lift_result({:ok, val}, env, st), do: ok(val, env, st)
  def lift_result({:error, reason}, env, _st), do: error(reason, env)

  @spec lift_bool(boolean(), term(), var_env(), Maty.ST.t()) :: result(nil) when a: var
  def lift_bool(true, _error, env, st), do: ok(nil, env, st)
  def lift_bool(false, error, env, _st), do: error(error, env)

  @doc """
  Prepend a context frame (see `Maty.Typechecker.Error.frame/0`) onto any
  structured error bubbling through this result, so the reporting site can
  show the propagation path.
  """
  @spec with_frame(t(a) | {:error, term()} | :ok, Error.frame()) :: t(a) | {:error, term()} | :ok
        when a: var
  def with_frame({:error, %Error{} = e, env}, frame),
    do: {:error, %{e | trace: [frame | e.trace]}, env}

  def with_frame({:error, %Error{} = e}, frame),
    do: {:error, %{e | trace: [frame | e.trace]}}

  def with_frame(other, _frame), do: other
end
