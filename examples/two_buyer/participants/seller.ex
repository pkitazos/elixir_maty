defmodule TwoBuyer.Participants.Seller do
  use Maty.Actor, protocol: TwoBuyer.Protocol

  # across all sessions: how many orders and quits the seller has seen
  global_state %{orders: number(), quits: number()}
  # in one session: the price quoted to the buyers
  local_state :seller, %{price: number()}

  session_type :seller, %{
    install: ~q"title_handler",
    title_handler: ~q"&buyer1:{title(binary).+buyer1:{quote(number).decision_handler}}",
    decision_handler: ~q"&buyer2:{address(binary).+buyer2:{date(number).end},quit(nil).end}"
  }

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :seller, &install/2, ap_pid)
    %{orders: 0, quits: 0}
  end

  defhandler install(ap_pid :: pid(), state) do
    Maty.DSL.register(ap_pid, :seller, &install/2, ap_pid)

    # an init handler starts with no local state, so it sets one up for the session
    Maty.DSL.suspend(&title_handler/3, %{global: state.global, local: %{price: 0}})
  end

  defhandler title_handler(:buyer1, {:title, title}, state) do
    IO.puts("&buyer1 : title(binary)")
    :timer.sleep(100)

    amount = lookup_price(title)
    Maty.DSL.send_to(:buyer1, {:quote, amount})
    IO.puts("+buyer1 : quote(number)")
    :timer.sleep(100)

    Maty.DSL.suspend(&decision_handler/3, %{state | local: %{price: amount}})
  end

  defhandler decision_handler(:buyer2, {:address, addr}, state) do
    IO.puts("&buyer2 : address(binary)")
    :timer.sleep(100)

    date = shipping_date(addr)
    Maty.DSL.send_to(:buyer2, {:date, date})
    IO.puts("+buyer2 : date(number)")
    :timer.sleep(100)

    orders = state.global.orders + 1
    IO.puts("seller: sold at #{state.local.price}, #{orders} order(s) so far")

    Maty.DSL.done(%{state | global: %{state.global | orders: orders}})
  end

  defhandler decision_handler(:buyer2, {:quit, nil}, state) do
    IO.puts("&buyer2 : quit()")
    :timer.sleep(100)

    quits = state.global.quits + 1
    IO.puts("seller: no sale at #{state.local.price}, #{quits} quit(s) so far")

    Maty.DSL.done(%{state | global: %{state.global | quits: quits}})
  end

  @spec lookup_price(binary()) :: number()
  defp lookup_price("Types and Programming Languages"), do: 150
  defp lookup_price(_title_str), do: 250

  @spec shipping_date(binary()) :: number()
  defp shipping_date(_addr_str), do: 20_211_231
end
