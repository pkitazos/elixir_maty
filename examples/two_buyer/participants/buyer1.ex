defmodule TwoBuyer.Participants.Buyer1 do
  use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:buyer1]

  global_state nil
  local_state :buyer1, %{}

  @st {:install, ~q/+seller:{title(binary).quote_handler}/}
  @st {:quote_handler, ~q/&seller:{quote(number).+buyer2:{share(number).end}}/}

  on_start {ap_pid, title} :: {pid(), binary()} do
    Maty.DSL.register(ap_pid, :buyer1, &install/2, title)
    nil
  end

  defhandler install(title :: binary(), state) do
    Maty.DSL.send_to(:seller, {:title, title})
    IO.puts("+seller : title(binary)")
    :timer.sleep(100)

    Maty.DSL.suspend(&quote_handler/3, state)
  end

  defhandler quote_handler(:seller, {:quote, amount :: number()}, state) do
    IO.puts("&seller : quote(number)")
    :timer.sleep(100)

    share_amount = amount / 2

    Maty.DSL.send_to(:buyer2, {:share, share_amount})
    IO.puts("+buyer2 : share(number)")
    :timer.sleep(100)

    Maty.DSL.done(state)
  end
end
