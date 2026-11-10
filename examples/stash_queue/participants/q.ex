defmodule StashQueue.Participants.Q do
  use Maty.Actor, protocol: StashQueue.Protocol, roles: [:q]

  global_state nil
  local_state :q, %{}

  @st {:install, ~q/p1_handler/}
  @st {:p1_handler, ~q/&p:{a(number).r1_handler}/}
  @st {:r1_handler, ~q/&r:{b(number).r2_handler}/}
  @st {:r2_handler, ~q/&r:{b(number).p2_handler}/}
  @st {:p2_handler, ~q/&p:{a(number).end}/}

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :q, &install/2, nil)
    nil
  end

  # Q waits until all four messages are in its mailbox before it starts reading it.
  # (If it read them as they arrived, an unexpected message would be re-queued over and over
  # until the expected one showed up, and the reordering would only happen by chance)
  defhandler install(nil, state) do
    :timer.sleep(500)
    Maty.DSL.suspend(&p1_handler/3, state)
  end

  defhandler p1_handler(:p, {:a, n :: number()}, state) do
    IO.puts("received a=#{n} from P")
    Maty.DSL.suspend(&r1_handler/3, state)
  end

  defhandler r1_handler(:r, {:b, n :: number()}, state) do
    IO.puts("received b=#{n} from R")
    Maty.DSL.suspend(&r2_handler/3, state)
  end

  defhandler r2_handler(:r, {:b, n :: number()}, state) do
    IO.puts("received b=#{n} from R")
    Maty.DSL.suspend(&p2_handler/3, state)
  end

  defhandler p2_handler(:p, {:a, n :: number()}, state) do
    IO.puts("received a=#{n} from P")
    Maty.DSL.done(state)
  end
end
