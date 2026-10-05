defmodule StashQueue.Participants.P do
  use Maty.Actor

  @role :p

  @st {:install, ~q/+q:{a(number).+q:{a(number).end}}/}

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
  # P waits so R's first message lands first, then sends both messages together so they land before R's second
  init_handler :install, {n1, n2} :: {number(), number()}, state do
    :timer.sleep(100)

    MatyDSL.send(:q, {:a, n1})
    MatyDSL.send(:q, {:a, n2})

    MatyDSL.done(state)
  end
end
