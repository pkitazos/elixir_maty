defmodule Maty.Typechecker.TC.IO do
  alias Maty.Typechecker.{TC, Error}

  import Maty.Utils, only: [deftc: 2]
  import Maty.Typechecker.TC.Thread
  import Maty.Typechecker.TC.Bind

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _meta1, [IO, :puts]}, meta, [arg]}
        ) do
    thread do
      arg_type <~ TC.tc_expr(ctx, env, st, arg)

      if arg_type in [:binary, {:list, :binary}] do
        ok(:atom, env, st)
      else
        error(
          Error.TypeMismatch.builtin_arg_type_mismatch(ctx.module, meta, "IO.puts",
            expected: [:binary, {:list, :binary}],
            got: arg_type
          ),
          env
        )
      end
    end
  end

  # catch-all for other IO functions (IO.inspect, IO.write, etc.)
  deftc tc_expr(_ctx, env, st, {{:., _meta1, [IO, _func]}, _meta2, _args}) do
    ok(:atom, env, st)
  end
end
