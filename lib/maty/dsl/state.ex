defmodule Maty.DSL.State do
  @behaviour Access

  alias Maty.Types

  defstruct [:sessions, :callbacks]

  @impl Access
  def fetch(state, key) when key in [:sessions, :callbacks] do
    Map.fetch(state, key)
  end

  @impl Access
  def get_and_update(state, key, function) when key in [:sessions, :callbacks] do
    current_value = Map.get(state, key)
    {get_value, new_value} = function.(current_value)
    new_state = Map.put(state, key, new_value)
    {get_value, new_state}
  end

  @impl Access
  def pop(state, key) when key in [:sessions, :callbacks] do
    {Map.get(state, key), Map.put(state, key, nil)}
  end

  def new do
    %Maty.DSL.State{sessions: %{}, callbacks: %{}}
  end

  def set(state, local_state, {session, _}) do
    put_in(state, [:sessions, session.id, :local_state], local_state)
  end

  defmacro set(state, local_state) do
    quote do
      Maty.DSL.State.set(unquote(state), unquote(local_state), var!(session_ctx))
    end
  end

  @spec get(Types.maty_actor_state()) :: map()
  def internal_get(state, {session, _}) do
    get_in(state, [:sessions, session.id, :local_state])
  end

  defmacro get(state) do
    quote do
      Maty.DSL.State.get(unquote(state), var!(session_ctx))
    end
  end
end
