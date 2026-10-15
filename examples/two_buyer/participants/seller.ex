defmodule TwoBuyer.Participants.Seller do
  use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

  @st {:install, ~q"title_handler"}
  @st {:title_handler, ~q"&buyer1:{title(binary).+buyer1:{quote(number).decision_handler}}"}
  @st {:decision_handler, ~q"&buyer2:{address(binary).+buyer2:{date(date).end},quit(nil).end}"}

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :seller, :install, ap_pid, %{})
    {:ok, %{}}
  end

  init_handler :install, ap_pid :: pid(), state do
    Maty.DSL.register(ap_pid, :seller, :install, ap_pid, %{})

    Maty.DSL.suspend(:title_handler, state)
  end

  handler :title_handler, :buyer1, {:title, title :: binary()}, state do
    IO.puts("&buyer1 : title(binary)")
    :timer.sleep(500)

    amount = lookup_price(title)
    Maty.DSL.send(:buyer1, {:quote, amount})
    IO.puts("+buyer1 : quote(number)")
    :timer.sleep(500)

    Maty.DSL.suspend(:decision_handler, state)
  end

  handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
    IO.puts("&buyer2 : address(binary)")
    :timer.sleep(500)

    date = shipping_date(addr)
    Maty.DSL.send(:buyer2, {:date, date})
    IO.puts("+buyer2 : date(date)")
    :timer.sleep(500)

    Maty.DSL.done(state)
  end

  handler :decision_handler, :buyer2, {:quit, nil}, state do
    IO.puts("&buyer2 : quit()")
    :timer.sleep(500)

    Maty.DSL.done(state)
  end

  @spec lookup_price(binary()) :: number()
  defp lookup_price(_title_str), do: 150

  @spec shipping_date(binary()) :: Date.t()
  defp shipping_date(_addr_str), do: ~D[2021-12-31]
end
