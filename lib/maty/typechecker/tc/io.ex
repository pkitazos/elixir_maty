defmodule Maty.Typechecker.TC.IO do
  alias Maty.Typechecker.TC

  def tc_expr(
        ctx,
        var_env,
        st_pre,
        {{:., _meta1, [IO, :puts]}, _meta2, [arg]}
      ) do
    case TC.tc_expr(ctx, var_env, st_pre, arg) do
      {:ok, {arg_type, ^st_pre}, updated_env} ->
        if arg_type in [:binary, {:list, :binary}] do
          {:ok, {:atom, st_pre}, updated_env}
        else
          {:error, "IO.puts expects a string argument, got: #{inspect(arg_type)}", updated_env}
        end

      {:error, _msg, _env} = error ->
        error
    end
  end

  # catch-all for other IO functions (IO.inspect, IO.write, etc.)
  def tc_expr(_ctx, var_env, st_pre, {{:., _meta1, [IO, _func]}, _meta2, _args}) do
    {:ok, {:atom, st_pre}, var_env}
  end
end
