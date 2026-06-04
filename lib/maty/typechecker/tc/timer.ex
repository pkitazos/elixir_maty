defmodule Maty.Typechecker.TC.Timer do
  alias Maty.Typechecker.TC

  import Maty.Utils, only: [deftc: 2]
  import Maty.Typechecker.TC.Thread
  import Maty.Typechecker.TC.Bind

  deftc tc_expr(
          ctx,
          env,
          st,
          {{:., _meta1, [:timer, :sleep]}, _meta2, [arg]}
        ) do
    thread do
      arg_type <~ TC.tc_expr(ctx, env, st, arg)

      if arg_type == :number do
        ok(:atom, env, st)
      else
        error(":timer.sleep expects a number argument, got: #{inspect(arg_type)}", env)
      end
    end
  end
end
