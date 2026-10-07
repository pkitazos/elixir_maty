defmodule Maty.AccessPoint do
  alias Maty.Types

  require Logger

  @spec start_link([Types.role()]) :: {:ok, pid()}
  def start_link(roles) do
    pid = spawn_link(fn -> loop(Map.from_keys(roles, :queue.new())) end)
    {:ok, pid}
  end

  @spec loop(Types.access_point_state()) :: no_return()
  defp loop(state) do
    receive do
      {:register, role, pid, init_token} ->
        updated_state = Map.update!(state, role, &:queue.in({pid, init_token}, &1))

        case take_participants(updated_state) do
          {:ok, mailing_list, address_book, remaining_state} ->
            session_id = make_ref()

            for {pid, tok} <- mailing_list do
              send(pid, {:init_session, session_id, address_book, tok})
            end

            loop(remaining_state)

          :not_ready ->
            loop(updated_state)
        end

      other ->
        Logger.warning(
          "[#{inspect(__MODULE__)}] discarding unexpected message: #{inspect(other)}"
        )

        loop(state)
    end
  end

  @type address_book :: %{Types.role() => pid()}
  @type mailing_list :: list(Types.candidate())

  @typep acc :: {:ok, mailing_list(), address_book(), Types.access_point_state()}

  # takes the first candidate from every role's queue
  # if any queue is empty, no session can start yet
  @spec take_participants(Types.access_point_state()) :: acc() | :not_ready
  defp take_participants(state) do
    Enum.reduce_while(state, {:ok, [], %{}, %{}}, &take_head/2)
  end

  @spec take_head({Types.role(), :queue.queue(Types.candidate())}, acc()) ::
          {:cont, acc()} | {:halt, :not_ready}
  defp take_head({role, queue}, {:ok, mailing, book, remaining}) do
    case :queue.out(queue) do
      {{:value, {pid, tok}}, rest} ->
        mailing = [{pid, tok} | mailing]
        book = Map.put(book, role, pid)
        remaining = Map.put(remaining, role, rest)
        {:cont, {:ok, mailing, book, remaining}}

      {:empty, _} ->
        {:halt, :not_ready}
    end
  end
end
