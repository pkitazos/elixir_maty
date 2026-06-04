defmodule Maty.Typechecker.TC.Thread do
  @moduledoc """
  Flat do-notation for the env + session-type threaded checker.

  Inside `thread do ... end`, each `pat <~ step` line runs `step` against the
  current `env`/`st`, rebinds them to what the step threads back, and binds
  `pat` to the produced value. The first failure short-circuits the block.
  Two line shapes:

      pat <~ expr     value step:  expr -> {:ok, {value, st}, env} | {:error, reason, env}
      :ok <~ expr     assertion:   expr -> :ok | {:error, reason}

  The trailing expression is the block's result (return it via `ok/3`).
  """

  defmacro thread(do: block) do
    stmts =
      case block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    build(stmts)
  end

  defp build([result]), do: result

  defp build([{:<~, _, [:ok, expr]} | rest]) do
    quote do
      case unquote(expr) do
        :ok -> unquote(build(rest))
        {:error, reason} -> {:error, reason, var!(env)}
      end
    end
  end

  defp build([{:<~, _, [pat, expr]} | rest]) do
    quote do
      case unquote(expr) do
        {:ok, {unquote(pat), new_st}, new_env} ->
          var!(env) = new_env
          var!(st) = new_st
          unquote(build(rest))

        {:error, _, _} = err ->
          err
      end
    end
  end
end
