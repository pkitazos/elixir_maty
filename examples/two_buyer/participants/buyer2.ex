defmodule TwoBuyer.Participants.Buyer2 do
  use Maty.Actor

  @role :buyer2

  @st {:install, "share_handler"}
  @st {:share_handler,
       "&buyer1:{share(number).+seller:{address(binary).date_handler, quit(nil).end}}"}
  @st {:date_handler, "&seller:{date(date).end}"}

  on_link ap_pid :: pid(), initial_state do
    MatyDSL.register(
      ap_pid,
      @role,
      [callback: :install, args: nil],
      initial_state
    )
  end

  init_handler :install, nil, state do
    MatyDSL.suspend(:share_handler, state)
  end

  handler :share_handler, :buyer1, {:share, amount :: number()}, state do
    IO.puts("&buyer1 : share(number)")
    :timer.sleep(500)

    if amount > 100 do
      MatyDSL.send(:seller, {:quit, nil})
      IO.puts("+seller : quit()")
      :timer.sleep(500)

      MatyDSL.done(state)
    else
      address = get_address()

      MatyDSL.send(:seller, {:address, address})
      IO.puts("+seller : address(binary)")
      :timer.sleep(500)

      MatyDSL.suspend(:date_handler, state)
    end
  end

  handler :date_handler, :seller, {:date, _date :: Date.t()}, state do
    IO.puts("&seller : date(date)")
    :timer.sleep(500)

    MatyDSL.done(state)
  end

  @spec get_address() :: binary()
  defp get_address(), do: "18 " <> "Lilybank Gardens"
end
