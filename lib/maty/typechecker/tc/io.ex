defmodule Maty.Typechecker.TC.IO do
  alias Maty.Typechecker.TC

  import Maty.Utils, only: [deftc: 2]
  import Maty.Typechecker.TC.Thread
  import Maty.Typechecker.TC.Bind

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _meta1, [IO, :puts]}, _meta2, [arg]}
        ) do
    thread do
      arg_type <~ TC.tc_expr(ctx, env, st, arg)

      if arg_type in [:binary, {:list, :binary}] do
        ok(:atom, env, st)
      else
        error("IO.puts expects a string argument, got: #{inspect(arg_type)}", env)
      end
    end
  end

  # catch-all for other IO functions (IO.inspect, IO.write, etc.)
  deftc tc_expr(_ctx, env, st, {{:., _meta1, [IO, _func]}, _meta2, _args}) do
    ok(:atom, env, st)
  end
end
