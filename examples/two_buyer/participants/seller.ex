defmodule TwoBuyer.Participants.Seller do
  use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

  global_state nil
  local_state :seller, nil

  @st {:install, ~q"title_handler"}
  @st {:title_handler, ~q"&buyer1:{title(binary).+buyer1:{quote(number).decision_handler}}"}
  @st {:decision_handler, ~q"&buyer2:{address(binary).+buyer2:{date(number).end},quit(nil).end}"}

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :seller, &install/2, ap_pid)
    nil
  end

  defhandler install(ap_pid :: pid(), state) do
    Maty.DSL.register(ap_pid, :seller, &install/2, ap_pid)

    Maty.DSL.suspend(&title_handler/3, state)
  end

  defhandler title_handler(:buyer1, {:title, title :: binary()}, state) do
    IO.puts("&buyer1 : title(binary)")
    :timer.sleep(100)

    amount = lookup_price(title)
    Maty.DSL.send_to(:buyer1, {:quote, amount})
    IO.puts("+buyer1 : quote(number)")
    :timer.sleep(100)

    Maty.DSL.suspend(&decision_handler/3, state)
  end

  defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
    IO.puts("&buyer2 : address(binary)")
    :timer.sleep(100)

    date = shipping_date(addr)
    Maty.DSL.send_to(:buyer2, {:date, date})
    IO.puts("+buyer2 : date(number)")
    :timer.sleep(100)

    Maty.DSL.done(state)
  end

  defhandler decision_handler(:buyer2, {:quit, nil}, state) do
    IO.puts("&buyer2 : quit()")
    :timer.sleep(100)

    Maty.DSL.done(state)
  end

  @spec lookup_price(binary()) :: number()
  defp lookup_price(_title_str), do: 150

  @spec shipping_date(binary()) :: number()
  defp shipping_date(_addr_str), do: 20_211_231
end
