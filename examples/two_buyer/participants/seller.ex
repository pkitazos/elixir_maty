defmodule TwoBuyer.Participants.Seller do
  use Maty.Actor

  @role :seller

  @st {:install, "title_handler"}
  @st {:title_handler, "&buyer1:{title(binary).+buyer1:{quote(number).decision_handler}}"}
  @st {:decision_handler, "&buyer2:{address(binary).+buyer2:{date(date).end},quit(nil).end}"}

  @impl true
  @spec on_link(pid(), maty_actor_state()) :: {:ok, maty_actor_state()}
  def on_link(ap_pid, initial_state) do
    MatyDSL.register(
      ap_pid,
      @role,
      [callback: :install, args: [ap_pid]],
      initial_state
    )
  end

  init_handler :install, ap_pid :: pid(), state do
    {:ok, updated_state} =
      MatyDSL.register(
        ap_pid,
        @role,
        [callback: :install, args: [ap_pid]],
        state
      )

    MatyDSL.suspend(:title_handler, updated_state)
  end

  handler :title_handler, :buyer1, {:title, title :: binary()}, state do
    amount = lookup_price(title)
    MatyDSL.send(:buyer1, {:quote, amount})
    MatyDSL.suspend(:decision_handler, state)
  end

  handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
    date = shipping_date(addr)
    MatyDSL.send(:buyer2, {:date, date})
    MatyDSL.done(state)
  end

  handler :decision_handler, :buyer2, {:quit, nil}, state do
    MatyDSL.done(state)
  end

  @spec lookup_price(binary()) :: number()
  defp lookup_price(_title_str), do: 150

  @spec shipping_date(binary()) :: Date.t()
  defp shipping_date(_addr_str), do: ~D[2021-12-31]
end
