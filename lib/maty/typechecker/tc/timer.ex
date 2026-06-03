defmodule Maty.Typechecker.TC.Timer do
  alias Maty.Typechecker.TC

  def tc_expr(
        ctx,
        var_env,
        st_pre,
        {{:., _meta1, [:timer, :sleep]}, _meta2, [arg]}
      ) do
    case TC.tc_expr(ctx, var_env, st_pre, arg) do
      {:ok, {:number, ^st_pre}, updated_env} ->
        {:ok, {:atom, st_pre}, updated_env}

      {:ok, {other_type, ^st_pre}, updated_env} ->
        {:error, ":timer.sleep expects a number argument, got: #{inspect(other_type)}",
         updated_env}

      {:error, _msg, _env} = error ->
        error
    end
  end
end
