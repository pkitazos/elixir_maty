defmodule TwoBuyer.Participants.Seller do
  use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

  @st {:install, ~q"title_handler"}
  @st {:title_handler, ~q"&buyer1:{title(binary).+buyer1:{quote(number).decision_handler}}"}
  @st {:decision_handler, ~q"&buyer2:{address(binary).+buyer2:{date(date).end},quit(nil).end}"}

  # ? does the state variable need to be here for linking into multiple sessions?
  # the reason it's actually needed is because this "state" variable also carries the actual runtime information.
  # which come to think of, we don't want the handler to even have access to.
  # we probably ought to hide that away from them as another threaded arg
  on_link ap_pid :: pid(), initial_state do
    MatyDSL.register(ap_pid, :seller, :install, ap_pid, initial_state)
  end

  init_handler :install, ap_pid :: pid(), state_l, state_g do
    {:ok, updated_state_g} = MatyDSL.register(ap_pid, :seller, :install, ap_pid, state_g)

    MatyDSL.suspend(:title_handler, state_l, updated_state_g)
  end

  # could make the state here a tuple and choose whether it gets destructured or not on a case-by-case basis.
  # for example when it's just threaded through, why bother destructuring it
  handler :title_handler, :buyer1, {:title, title :: binary()}, state_l, state_g do
    IO.puts("&buyer1 : title(binary)")
    :timer.sleep(500)

    amount = lookup_price(title)
    MatyDSL.send(:buyer1, {:quote, amount})
    IO.puts("+buyer1 : quote(number)")
    :timer.sleep(500)

    MatyDSL.suspend(:decision_handler, state_l, state_g)
  end

  handler :decision_handler, :buyer2, {:address, addr :: binary()}, state_l, state_g do
    IO.puts("&buyer2 : address(binary)")
    :timer.sleep(500)

    date = shipping_date(addr)
    MatyDSL.send(:buyer2, {:date, date})
    IO.puts("+buyer2 : date(date)")
    :timer.sleep(500)

    MatyDSL.done(state_l, state_g)
  end

  handler :decision_handler, :buyer2, {:quit, nil}, state_l, state_g do
    IO.puts("&buyer2 : quit()")
    :timer.sleep(500)

    MatyDSL.done(state_l, state_g)
  end

  @spec lookup_price(binary()) :: number()
  defp lookup_price(_title_str), do: 150

  @spec shipping_date(binary()) :: Date.t()
  defp shipping_date(_addr_str), do: ~D[2021-12-31]
end
