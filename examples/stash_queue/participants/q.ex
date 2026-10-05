defmodule StashQueue.Participants.Q do
  use Maty.Actor

  @role :q

  @st {:install, ~q/p1_handler/}
  @st {:p1_handler, ~q/&p:{a(number).r1_handler}/}
  @st {:r1_handler, ~q/&r:{b(number).r2_handler}/}
  @st {:r2_handler, ~q/&r:{b(number).p2_handler}/}
  @st {:p2_handler, ~q/&p:{a(number).end}/}

  on_link ap_pid :: pid(), initial_state do
    MatyDSL.register(
      ap_pid,
      @role,
      :install,
      nil,
      initial_state
    )
  end

  # Q waits until all four messages are in its mailbox before it starts reading it.
  # (If it read them as they arrived, an unexpected message would be re-queued over and over
  # until the expected one showed up, and the reordering would only happen by chance)
  init_handler :install, nil, state do
    :timer.sleep(500)
    MatyDSL.suspend(:p1_handler, state)
  end

  handler :p1_handler, :p, {:a, n :: number()}, state do
    IO.puts("received a=#{n} from P")
    MatyDSL.suspend(:r1_handler, state)
  end

  handler :r1_handler, :r, {:b, n :: number()}, state do
    IO.puts("received b=#{n} from R")
    MatyDSL.suspend(:r2_handler, state)
  end

  handler :r2_handler, :r, {:b, n :: number()}, state do
    IO.puts("received b=#{n} from R")
    MatyDSL.suspend(:p2_handler, state)
  end

  handler :p2_handler, :p, {:a, n :: number()}, state do
    IO.puts("received a=#{n} from P")
    MatyDSL.done(state)
  end
end
