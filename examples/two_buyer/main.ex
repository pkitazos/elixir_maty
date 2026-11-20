defmodule TwoBuyer.Main do
  alias TwoBuyer.Participants.{Seller, Buyer1, Buyer2}

  def start do
    IO.puts("main process: #{inspect(self())}")

    {:ok, ap} = Maty.AccessPoint.start_link(TwoBuyer.Protocol)
    IO.puts("access point started at: #{inspect(ap)}")

    {:ok, seller_pid} = Seller.start_link(ap)
    IO.puts("seller started at: #{inspect(seller_pid)}")

    spawn_buyers(ap, "Types and Programming Languages")
    IO.puts("---")
    # a pricier book, so buyer2 quits this time
    spawn_buyers(ap, "Compiling with Continuations")

    # Give time for all processes to complete their communication
    :timer.sleep(2000)
  end

  defp spawn_buyers(ap, title) do
    {:ok, buyer1_pid} = Buyer1.start_link({ap, title})
    IO.puts("buyer1 started at: #{inspect(buyer1_pid)}")
    {:ok, buyer2_pid} = Buyer2.start_link(ap)
    IO.puts("buyer2 started at: #{inspect(buyer2_pid)}")
    :ok
  end
end
