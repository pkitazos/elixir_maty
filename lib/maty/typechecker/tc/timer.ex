defmodule Maty.Typechecker.TC.Timer do
  alias Maty.Typechecker.Error

  import Maty.Check
  import Maty.Utils, only: [deftc: 2]

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _meta1, [:timer, :sleep]}, meta, [arg]}
        ) do
    # or could just not typecheck this..
    tcm env: env, st: st do
      arg_type <- tc(ctx, arg)

      expect arg_type == :number,
        else:
          Error.TypeMismatch.builtin_arg_type_mismatch(ctx.module, meta, ":timer.sleep",
            expected: :number,
            got: arg_type
          )

      ok(:atom)
    end
  end
end
