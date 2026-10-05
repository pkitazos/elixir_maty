defmodule StashQueue.Main do
  alias StashQueue.Participants.{P, Q, R}

  def start do
    # IO.puts("main process: #{inspect(self())}")

    {:ok, ap} = Maty.AccessPoint.start_link([:p, :q, :r])
    # IO.puts("access point started at: #{inspect(ap)}")

    {:ok, _q_pid} = Q.start_link(ap)
    # IO.puts("Q started at: #{inspect(q_pid)}")

    {:ok, _p_pid} = P.start_link({ap, {10, 20}})
    # IO.puts("Q started at: #{inspect(p_pid)}")
    {:ok, _r_pid} = R.start_link({ap, {5, 15}})
    # IO.puts("Q started at: #{inspect(r_pid)}")

    # Give time for all processes to complete their communication
    :timer.sleep(1000)
  end
end
