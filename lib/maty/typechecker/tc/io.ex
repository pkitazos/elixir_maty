defmodule Maty.Typechecker.TC.IO do
  alias Maty.Typechecker.Error

  import Maty.Utils, only: [deftc: 2]
  import Maty.Check

  deftc synth(
          ctx,
          env,
          st,
          {{:., _meta1, [IO, :puts]}, meta, [arg]}
        ) do
    # or could just not typecheck this..
    tcm env: env, st: st do
      arg_type <- syn(ctx, arg)

      expect arg_type in [:binary, {:list, :binary}],
        else:
          Error.TypeMismatch.builtin_arg_type_mismatch(ctx.module, meta, "IO.puts",
            expected: [:binary, {:list, :binary}],
            got: arg_type
          )

      ok(:atom)
    end
  end

  # catch-all for other IO functions (IO.inspect, IO.write, etc.)
  deftc synth(_ctx, env, st, {{:., _meta1, [IO, _func]}, _meta2, _args}) do
    {:ok, :atom, st, env}
  end
end
