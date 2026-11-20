defmodule TwoBuyer.Participants.Buyer2 do
  use Maty.Actor, protocol: TwoBuyer.Protocol

  global_state nil
  local_state :buyer2, nil

  session_type :buyer2, %{
    install: ~q"share_handler",
    share_handler:
      ~q"&buyer1:{share(number).+seller:{address(binary).date_handler, quit(nil).end}}",
    date_handler: ~q"&seller:{date(number).end}"
  }

  on_start ap_pid :: pid() do
    Maty.DSL.register(ap_pid, :buyer2, &install/2, nil)
    nil
  end

  defhandler install(nil, state) do
    Maty.DSL.suspend(&share_handler/3, state)
  end

  defhandler share_handler(:buyer1, {:share, amount}, state) do
    IO.puts("&buyer1 : share(number)")
    :timer.sleep(100)

    if amount > 100 do
      Maty.DSL.send_to(:seller, {:quit, nil})
      IO.puts("+seller : quit()")
      :timer.sleep(100)

      Maty.DSL.done(state)
    else
      address = get_address()

      Maty.DSL.send_to(:seller, {:address, address})
      IO.puts("+seller : address(binary)")
      :timer.sleep(100)

      Maty.DSL.suspend(&date_handler/3, state)
    end
  end

  defhandler date_handler(:seller, {:date, _date}, state) do
    IO.puts("&seller : date(number)")
    :timer.sleep(100)

    Maty.DSL.done(state)
  end

  @spec get_address() :: binary()
  defp get_address(), do: "18 " <> "Lilybank Gardens"
end
