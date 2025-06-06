defmodule Maty.AccessPoint do
  alias Maty.Types

  @spec start_link([Types.role()]) :: {:ok, pid()}
  def start_link(roles) do
    initial_state = %{participants: Map.from_keys(roles, :queue.new())}

    pid = spawn_link(fn -> loop(initial_state) end)
    {:ok, pid}
  end

  @spec loop(%{
          participants: %{required(Types.role()) => :queue.queue({pid(), Types.init_token()})}
        }) :: no_return()
  defp loop(%{participants: participants} = state) do
    receive do
      {:register, role, pid, init_token} ->
        new_participants = Map.update!(participants, role, &:queue.in({pid, init_token}, &1))

        if not session_ready?(new_participants) do
          loop(%{state | participants: new_participants})
        end

        session_id = make_ref()

        {ready_participants, updated_participants} = get_ready_participants!(new_participants)

        session_participants =
          ready_participants
          |> Enum.map(fn {pid, role, _} -> {role, pid} end)
          |> Enum.into(%{})

        ready_participants
        |> Enum.map(fn {pid, _, token} ->
          send(pid, {:init_session, session_id, session_participants, token})
        end)

        loop(%{state | participants: updated_participants})
    end
  end

  @spec session_ready?(%{Types.role() => :queue.queue({pid(), Types.init_token()})}) :: boolean()
  def session_ready?(%{} = participants) do
    not Enum.any?(participants, fn {_, q} -> :queue.is_empty(q) end)
  end

  @spec get_ready_participants!(%{Types.role() => :queue.queue({pid(), Types.init_token()})}) ::
          {[{pid(), Types.role(), Types.init_token()}], %{Types.role() => :queue.queue()}}
  def get_ready_participants!(participants) do
    {ready_participants, role_queue_pairs} =
      participants
      |> Map.to_list()
      |> Enum.map(fn {role, q} ->
        {{:value, {pid, token}}, updated_queue} = :queue.out(q)
        {{pid, role, token}, {role, updated_queue}}
      end)
      |> Enum.unzip()

    {ready_participants, Enum.into(role_queue_pairs, %{})}
  end
end
