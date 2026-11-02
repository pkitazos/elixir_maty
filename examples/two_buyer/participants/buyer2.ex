defmodule TwoBuyer.Participants.Buyer2 do
  use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:buyer2]

  global_state %{}
  local_state :buyer2, %{}

  @st {:install, ~q"share_handler"}
  @st {:share_handler,
       ~q"&buyer1:{share(number).+seller:{address(binary).date_handler, quit(nil).end}}"}
  @st {:date_handler, ~q"&seller:{date(date).end}"}

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :buyer2, :install, nil)
    %{}
  end

  defhandler install(nil, state) do
    Maty.DSL.suspend(:share_handler, state)
  end

  defhandler share_handler(:buyer1, {:share, amount :: number()}, state) do
    IO.puts("&buyer1 : share(number)")
    :timer.sleep(500)

    if amount > 100 do
      Maty.DSL.send(:seller, {:quit, nil})
      IO.puts("+seller : quit()")
      :timer.sleep(500)

      Maty.DSL.done(state)
    else
      address = get_address()

      Maty.DSL.send(:seller, {:address, address})
      IO.puts("+seller : address(binary)")
      :timer.sleep(500)

      Maty.DSL.suspend(:date_handler, state)
    end
  end

  defhandler date_handler(:seller, {:date, _date :: Date.t()}, state) do
    IO.puts("&seller : date(date)")
    :timer.sleep(500)

    Maty.DSL.done(state)
  end

  @spec get_address() :: binary()
  defp get_address(), do: "18 " <> "Lilybank Gardens"
end
