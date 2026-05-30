defmodule TwoBuyer.Participants.Buyer1 do
  use Maty.Actor

  @role :buyer1

  @st {:install, "+seller:{title(binary).quote_handler}"}
  @st {:quote_handler, "&seller:{quote(number).+buyer2:{share(number).end}}"}

  on_link {ap_pid, title} :: {pid(), binary()}, initial_state do
    MatyDSL.register(
      ap_pid,
      @role,
      [callback: :install, args: [title]],
      initial_state
    )
  end

  init_handler :install, title :: binary(), state do
    MatyDSL.send(:seller, {:title, title})
    IO.puts("+seller : title(binary)")
    :timer.sleep(500)

    MatyDSL.suspend(:quote_handler, state)
  end

  handler :quote_handler, :seller, {:quote, amount :: number()}, state do
    IO.puts("&seller : quote(number)")
    :timer.sleep(500)

    share_amount = amount / 2

    MatyDSL.send(:buyer2, {:share, share_amount})
    IO.puts("+buyer2 : share(number)")
    :timer.sleep(500)

    MatyDSL.done(state)
  end
end
