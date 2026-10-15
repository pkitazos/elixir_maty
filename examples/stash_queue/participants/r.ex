defmodule StashQueue.Participants.R do
  use Maty.Actor, protocol: StashQueue.Protocol, roles: [:r]

  @st {:install, ~q/+q:{b(number).+q:{b(number).end}}/}

  on_start {ap_pid, {n1, n2}} :: {pid(), {number(), number()}} do
    Maty.DSL.register(ap_pid, :r, :install, {n1, n2}, %{})
    {:ok, %{}}
  end

  # the timings set up Q's mailbox as [b(n1), a(n1), a(n2), b(n2)] (see docs/stash-queue.md)
  # R's first message goes out at once, its second only after both of P's have landed
  init_handler :install, {n1, n2} :: {number(), number()}, state do
    Maty.DSL.send(:q, {:b, n1})

    :timer.sleep(300)
    Maty.DSL.send(:q, {:b, n2})

    Maty.DSL.done(state)
  end
end
