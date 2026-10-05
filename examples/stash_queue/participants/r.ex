defmodule StashQueue.Participants.R do
  use Maty.Actor

  @role :r

  @st {:install, ~q/+q:{b(number).+q:{b(number).end}}/}

  on_link {ap_pid, {n1, n2}} :: {pid(), {number(), number()}}, initial_state do
    MatyDSL.register(
      ap_pid,
      @role,
      :install,
      {n1, n2},
      initial_state
    )
  end

  # the timings set up Q's mailbox as [b(n1), a(n1), a(n2), b(n2)] (see docs/stash-queue.md)
  # R's first message goes out at once, its second only after both of P's have landed
  init_handler :install, {n1, n2} :: {number(), number()}, state do
    MatyDSL.send(:q, {:b, n1})

    :timer.sleep(300)
    MatyDSL.send(:q, {:b, n2})

    MatyDSL.done(state)
  end
end
