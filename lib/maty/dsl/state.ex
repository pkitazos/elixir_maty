defmodule Maty.DSL.State do
  @behaviour Access

  alias Maty.Types

  @type t :: %__MODULE__{
          sessions: %{Types.session_id() => Types.session()},
          callbacks: %{Types.init_token() => {Types.role(), Types.handler_label(), any()}},
          stash: list({Types.session_id(), Types.role(), Types.role(), Types.message()})
        }

  @state_keys [:sessions, :callbacks, :stash]
  defstruct @state_keys

  @impl Access
  def fetch(state, key) when key in @state_keys do
    Map.fetch(state, key)
  end

  @impl Access
  def get_and_update(state, key, function) when key in @state_keys do
    current_value = Map.get(state, key)
    {get_value, new_value} = function.(current_value)
    new_state = Map.put(state, key, new_value)
    {get_value, new_state}
  end

  @impl Access
  def pop(state, key) when key in @state_keys do
    {Map.get(state, key), Map.put(state, key, nil)}
  end

  def new do
    %Maty.DSL.State{sessions: %{}, callbacks: %{}, stash: []}
  end

  def set(state, local_state, {session, _}) do
    put_in(state, [:sessions, session.id, :local_state], local_state)
  end

  defmacro set(state, local_state) do
    quote do
      Maty.DSL.State.set(unquote(state), unquote(local_state), var!(session_ctx))
    end
  end

  @spec internal_get(Types.maty_actor_state(), Types.session_ctx()) :: map()
  def internal_get(state, {session, _}) do
    get_in(state, [:sessions, session.id, :local_state])
  end

  defmacro get(state) do
    quote do
      Maty.DSL.State.internal_get(unquote(state), var!(session_ctx))
    end
  end
end
