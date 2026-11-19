defmodule StashQueue.Participants.P do
  use Maty.Actor, protocol: StashQueue.Protocol, roles: [:p]

  global_state nil
  local_state :p, nil

  session_type :p, %{
    install: ~q/+q:{a(number).+q:{a(number).end}}/
  }

  on_start {ap_pid, {n1, n2}} :: {pid(), {number(), number()}} do
    Maty.DSL.register(ap_pid, :p, &install/2, {n1, n2})
    nil
  end

  # the timings set up Q's mailbox as [b(n1), a(n1), a(n2), b(n2)] (see docs/stash-queue.md)
  # P waits so R's first message lands first, then sends both messages together so they land before R's second
  defhandler install({n1, n2} :: {number(), number()}, state) do
    :timer.sleep(100)

    Maty.DSL.send_to(:q, {:a, n1})
    Maty.DSL.send_to(:q, {:a, n2})

    Maty.DSL.done(state)
  end
end
