defmodule Maty.Check do
  @moduledoc """
  New block for typechecking which should let me focus on just writing the logic
  and not worry too much about the plumbing involved.

  See blogpost for in-depth explanation of everything that's going on here
  """

  alias Maty.Typechecker.{Error, PatternBinding, TC}

  # -- Types

  @typedoc "Γ variable binding environment"
  @type var_env :: %{atom() => Maty.Types.T.t()}
  # The fixed per-module part (Ψ; Δ) is `Maty.Typechecker.Ctx`.

  @typedoc "running a step gives back its value `a` (with the new Q and Γ), or an error"
  @type result(a) :: {:ok, a, Maty.ST.t(), var_env()} | {:error, Error.t(), var_env()}

  @typedoc "An actual step takes in the previous Γ and Q and returns a result"
  @type t(a) :: (var_env(), Maty.ST.t() -> result(a))

  # -- combinators + friends

  # Right
  @spec ok(a) :: t(a) when a: var
  def ok(value), do: fn env, st -> {:ok, value, st, env} end

  # Right - but only for ending blocks with an updated session type
  @spec ok(a, st: Maty.ST.t()) :: t(a) when a: var
  def ok(value, st: next_st), do: fn env, _st -> {:ok, value, next_st, env} end

  @spec ok() :: t(nil)
  def ok, do: fn env, st -> {:ok, nil, st, env} end

  # Left
  @spec fail(Error.t()) :: t(none())
  def fail(error), do: fn env, _st -> {:error, error, env} end

  # >>=
  @spec bind(t(a), (a -> t(b))) :: t(b) when a: var, b: var
  def bind(check, fun) do
    fn env, st ->
      case apply_check(check, env, st) do
        {:ok, value, st, env} -> apply_check(fun.(value), env, st)
        {:error, _, _} = err -> err
      end
    end
  end

  # -- typing judgements + friends

  # todo: see if I can drop the meta param
  # Ψ; Δ; Γ ⊢ v : A
  @spec value(Maty.Typechecker.Ctx.t(), Macro.t(), keyword()) :: t(Maty.Types.T.t())
  def value(ctx, v, meta), do: st_preserving(ctx, tc(ctx, v), meta)

  # Ψ; Δ; Γ | Q₁ |> e : T <| Q₂
  @spec tc(Maty.Typechecker.Ctx.t(), Macro.t()) :: t(Maty.Types.T.t())
  def tc(ctx, e), do: fn env, st -> TC.tc_expr(ctx, env, st, e) end

  # ⊢ p : a ⇒ Γ'
  @spec match_pattern(Maty.Typechecker.Ctx.t(), Macro.t(), Maty.Types.T.t()) :: t(nil)
  def match_pattern(ctx, p, a) do
    fn env, st ->
      case PatternBinding.tc_pattern(ctx, p, a, env) do
        {:ok, _bindings, new_env} -> {:ok, nil, st, new_env}
        {:error, error, err_env} -> {:error, error, err_env}
      end
    end
  end

  # x : A ∈ Γ
  @spec lookup_var(atom(), Error.t()) :: t(Maty.Types.T.t())
  def lookup_var(name, error) do
    fn env, st ->
      case Map.fetch(env, name) do
        {:ok, type} -> {:ok, type, st, env}
        :error -> {:error, error, env}
      end
    end
  end

  @spec st_preserving(Maty.Typechecker.Ctx.t(), t(a), keyword()) :: t(a) when a: var
  def st_preserving(ctx, check, meta) do
    fn env, st_pre ->
      case apply_check(check, env, st_pre) do
        {:ok, _value, ^st_pre, _env} = ok ->
          ok

        {:ok, _value, st_post, env} ->
          {:error,
           Error.ProtocolViolation.value_altered_session_state(ctx.module, meta,
             from: st_pre,
             to: st_post
           ), env}

        {:error, _, _} = err ->
          err
      end
    end
  end

  # todo: can this not just be inlined?
  def __current_st__, do: fn env, st -> {:ok, st, st, env} end

  # -- multiple expressions

  # mapM / traverse
  @spec chain([a], (a -> t(b))) :: t([b]) when a: var, b: var
  def chain(items, fun) do
    fn env, st ->
      items
      |> Enum.reduce_while({:ok, [], st, env}, fn item, {:ok, acc, st, env} ->
        case apply_check(fun.(item), env, st) do
          {:ok, value, st, env} -> {:cont, {:ok, [value | acc], st, env}}
          {:error, _, _} = err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, rev, st, env} -> {:ok, Enum.reverse(rev), st, env}
        {:error, _, _} = err -> err
      end
    end
  end

  @spec fan_out([a], (a -> t(b))) :: t([{b, Maty.ST.t()}]) when a: var, b: var
  def fan_out(items, fun) do
    fn env, st ->
      results = Enum.map(items, fn item -> apply_check(fun.(item), env, st) end)

      case Enum.find(results, &match?({:error, _, _}, &1)) do
        {:error, error, _item_env} ->
          {:error, error, env}

        nil ->
          {:ok, Enum.map(results, fn {:ok, value, item_st, _env} -> {value, item_st} end), st,
           env}
      end
    end
  end

  # -- internals

  @doc false
  # what `check env: env, st: st_pre do` compiles to: run a check from a starting Γ and Q
  @spec __run__(t(a), env: var_env(), st: Maty.ST.t()) :: result(a) when a: var
  def __run__(check, start) when is_list(start) do
    case Enum.sort_by(start, &elem(&1, 0)) do
      [env: env, st: st] ->
        apply_check(check, env, st)

      other ->
        raise ArgumentError,
              "check expects exactly `env:` and `st:`, got: #{inspect(Keyword.keys(other))}"
    end
  end

  defp apply_check(check, env, st) when is_function(check, 2), do: check.(env, st)

  defp apply_check(other, _env, _st) do
    raise ArgumentError,
          "expected a check (a 2-arity function over env and st), got: #{inspect(other)}"
  end

  # -- errors

  @doc """
  Append a context frame (see `Maty.Typechecker.Error.frame/0`)
  to any structured error bubbling through this result, so the reporting site
  can show the propagation path.
  """
  @spec with_frame(t(a), Error.frame()) :: t(a) when a: var
  def with_frame(check, frame) do
    fn env, st ->
      case apply_check(check, env, st) do
        {:error, %Error{} = e, env} -> {:error, %{e | trace: e.trace ++ [frame]}, env}
        other -> other
      end
    end
  end

  # macro time!

  @doc "Builds a check from a sequence of statements"
  defmacro check(do: block), do: build_check(block)

  @doc "Builds a check and runs it from a starting Γ and Q"
  defmacro check(start, do: block) do
    quote do
      Maty.Check.__run__(unquote(build_check(block)), unquote(start))
    end
  end

  defp build_check(block) do
    # make sure there's no nested runs
    # because they would restart from the given state partway through a rule
    Macro.prewalk(block, &reject_check_run/1)

    # extract all the statements from the block
    stmts = statements(block)

    # make sure the last statement is the only one containing a "concluding statement"
    conclusion_last(stmts)

    # build the actual block
    build(stmts)
  end

  # -- (even further) internal

  defp statements({:__block__, _, list}), do: list
  defp statements(single), do: [single]

  # `ok(_, st: _)` sets Q₂, so it may only be the concluding statement of the block
  # (or the concluding statement of a branch of a final case/if/cond)
  defp conclusion_last(stmts) do
    {init, [last]} = Enum.split(stmts, -1)

    # make sure no non-last statement tries an `ok/2`
    for stmt <- init do
      Macro.prewalk(stmt, &reject_ok_st/1)
    end

    # make sure the last statement is allowed
    conclusion_tail(last)
  end

  defp reject_check_run({:check, meta, [_start, [do: _]]}),
    do:
      raise(CompileError,
        line: meta[:line],
        description:
          "`check env: _, st: _` cannot be used inside a check block (it would restart from the given state partway through the rule); use `check do` for nested blocks"
      )

  defp reject_check_run(other), do: other

  defp reject_ok_st({:ok, meta, [_, [{:st, _}]]}),
    do:
      raise(CompileError,
        line: meta[:line],
        description:
          "`ok(_, st: _)` is the rule's conclusion (T ◁ Q₂), so it must be the last statement of the check block"
      )

  # each check block checks itself so we don't need to walk further
  # any atom stops the walk
  defp reject_ok_st({:check, _, [[do: _]]}), do: nil
  defp reject_ok_st(other), do: other

  defp conclusion_tail({:case, _, [_, [do: clauses]]}), do: conclusion_clauses(clauses)
  defp conclusion_tail({:cond, _, [[do: clauses]]}), do: conclusion_clauses(clauses)

  defp conclusion_tail({:if, _, [_, branches]}) when is_list(branches),
    do: Enum.each(branches, fn {_, body} -> conclusion_last(statements(body)) end)

  defp conclusion_tail(_), do: :ok

  defp conclusion_clauses(clauses),
    do: Enum.each(clauses, fn {:->, _, [_, body]} -> conclusion_last(statements(body)) end)

  # -- (even further, further) internals

  # the last statement in a block must be a check (aka step)
  # the statement forms (`<-`, `=`, `expect`, `expect_st`) only make sense with more checks after them
  defp build([{form, meta, _}]) when form in [:<-, :=, :expect, :expect_st] do
    raise CompileError,
      line: meta[:line],
      description: "a check block must end in a check, not `#{form}`"
  end

  defp build([last]), do: last

  # the rest of the forms that we need to intercept and interpret

  # PAT <- check
  # PAT is just a plain var
  defp build([{:<-, _, [{name, _, ctx} = var, check]} | rest])
       when is_atom(name) and is_atom(ctx) do
    quote do
      Maty.Check.bind(unquote(check), fn unquote(var) -> unquote(build(rest)) end)
    end
  end

  # PAT is some actual pattern, so we need to try and match it
  defp build([{:<-, _, [pat, check]} | rest]) do
    quote do
      Maty.Check.bind(unquote(check), fn value ->
        case value do
          unquote(pat) -> unquote(build(rest))
          other -> raise MatchError, term: other
        end
      end)
    end
  end

  # PAT = expr
  # just let Elixir handle this
  defp build([{:=, _, [_pat, _expr]} = match | rest]) do
    quote do
      unquote(match)
      unquote(build(rest))
    end
  end

  # expect PAT = expr, else: err
  defp build([{:expect, _, [{:=, _, [pat, expr]}, [else: error]]} | rest]) do
    quote do
      case unquote(expr) do
        unquote(pat) -> unquote(build(rest))
        _ -> Maty.Check.fail(unquote(error))
      end
    end
  end

  # expect BOOL, else: err
  defp build([{:expect, _, [cond, [else: error]]} | rest]),
    do: condition(cond, error, build(rest))

  # expect_st PAT, else: fn q -> err_fun(q) end
  defp build([{:expect_st, _, [pat, [else: error_fun]]} | rest]) do
    quote do
      Maty.Check.bind(Maty.Check.__current_st__(), fn st ->
        case st do
          unquote(pat) -> unquote(build(rest))
          _ -> Maty.Check.fail(unquote(error_fun).(st))
        end
      end)
    end
  end

  # anything else just gets lifted to a `check` via `bind`
  defp build([check | rest]) do
    quote do
      Maty.Check.bind(unquote(check), fn _ -> unquote(build(rest)) end)
    end
  end

  # -- further, further internals' helpers

  defp condition(cond, error, continue) do
    quote do
      case unquote(cond) do
        true ->
          unquote(continue)

        false ->
          Maty.Check.fail(unquote(error))

        other ->
          # anything that is not a boolean is a bug in the rule
          raise ArgumentError,
                "`expect` without `=` needs a boolean condition, got: #{inspect(other)}"
      end
    end
  end
end
