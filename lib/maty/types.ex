defmodule Maty.Types do
  @moduledoc """
  Custom types used in Maty.
  """

  @type session_id :: reference()
  @type init_token :: reference()
  @type role :: atom()

  # a session consists of:
  # - an ID
  # - a map of session roles to pairs of (handlers x role you are being called as? not sure what this role is)
  # - the address book
  # - some session-local state

  @type session :: %{
          id: session_id(),
          handlers: %{role() => {function(), role()}},
          participants: %{role() => pid()},
          local_state: map()
        }

  # this is a custom wrapper type
  # a particular handler always needs some session context
  # that is, the actual session, and the role of the actor for the given handler
  @type session_ctx :: {session(), role()}

  # a Maty actor stores:
  # - a map of sessions it is participating in
  # - a map of initialisation token to pairs of (role x callback) to invoke when the session starts
  # - some global state (maybe not actually)
  @type maty_actor_state :: %{
          sessions: %{session_id() => session()},
          callbacks: %{init_token() => {role(), function()}},
          global_state: map()
        }

  # an access point stores a map of candidate participants
  # it maps roles to queues storing pairs of (PID x initialisation token)
  @type access_point_state :: %{
          participants: %{role() => :queue.queue({pid(), init_token()})}
        }

  # these are the names of our types
  @maty_types [
    :session_id,
    :init_token,
    :role,
    :session,
    :session_ctx,
    :maty_actor_state,
    :suspend,
    :done
  ]

  def get do
    @maty_types
  end

  # this maps our type names to their actual structural type
  def map do
    session_id = :ref
    init_token = :ref
    role = :atom

    session =
      {:map,
       %{
         id: session_id,
         handlers: {:map, %{role => {:tuple, [:function, role]}}},
         participants: {:map, %{role => :pid}},
         local_state: :any
       }}

    maty_actor_state =
      {:map,
       %{
         sessions: {:map, %{session_id => session}},
         callbacks: {:map, %{init_token => {:tuple, [role, :function]}}}
       }}

    %{
      session_id: session_id,
      init_token: init_token,
      role: role,
      session: session,
      session_ctx: {session, role},
      maty_actor_state: maty_actor_state
    }
  end

  # List of accepted types in session types
  @supported_payload_types [
    :atom,
    :binary,
    :boolean,
    :date,
    :number,
    :pid,
    :ref,
    nil
  ]

  @doc """
  Returns a list of all accepted types, including :number, :atom, ...
  """
  @spec payload_types ::
          nonempty_list(:atom | :binary | :boolean | :date | :number | :pid | :ref | nil)
  def payload_types() do
    @supported_payload_types
  end

  defmodule T do
    @typedoc """
    Represents types that are supported by the Maty typechecker.
    These are primitive types that can be checked directly.
    """
    @type t ::
            :any
            | :atom
            | :binary
            | :boolean
            | :date
            | nil
            | :number
            | :no_return
            | :pid
            | :ref
            | :maty_handler_msg
            | :maty_handler_init
            | {:fun, non_neg_integer()}
            | {:tuple, [t()]}
            | {:list, t()}
            | {:map, %{atom() => t()}}
            # todo: eventually eliminate bare :map
            # getState should return the properly typed actor state
            # which likely requires some form of type inference
            | :map

    def session_id, do: :ref
    def init_token, do: :ref
    def role, do: :atom

    def session,
      do:
        {:map,
         %{
           id: T.session_id(),
           handlers: {:map, %{T.role() => {:tuple, [:function, T.role()]}}},
           participants: {:map, %{T.role() => :pid}},
           local_state: :any
         }}

    def session_ctx, do: {:tuple, [T.session(), T.role()]}

    def maty_actor_state,
      do:
        {:map,
         %{
           sessions: {:map, %{T.session_id() => T.session()}},
           callbacks: {:map, %{T.init_token() => {:tuple, [T.role(), :function]}}}
         }}

    # ------------------------------------------------------------------

    # these are boolean functions which check if a given type is the same as some other type

    def is?(:ref, :session_id), do: true
    def is?(:ref, :init_token), do: true

    def is?(:atom, :role), do: true

    def is?({:map, map}, :session) do
      has_all_keys? =
        Map.has_key?(map, :id) and Map.has_key?(map, :handlers) and
          Map.has_key?(map, :participants) and Map.has_key?(map, :local_state)

      cond do
        not has_all_keys? ->
          false

        true ->
          %{
            id: session_id,
            handlers: {:map, handler_map},
            participants: {:map, participant_map},
            local_state: :any
          } = map

          s_valid? = is?(session_id, :session_id)

          h_valid? =
            handler_map
            |> Map.to_list()
            |> Enum.all?(fn {k, v} -> is?(k, :role) and v == {:tuple, [:function, T.role()]} end)

          p_valid? =
            participant_map
            |> Map.to_list()
            |> Enum.all?(fn {k, v} -> is?(k, :role) and v == :pid end)

          s_valid? and h_valid? and p_valid?
      end
    end

    # standardise what 2-tuple types look like
    def is?({session, role}, :session_ctx), do: is?(session, :session) and is?(role, :role)

    def is?({:tuple, [session, role]}, :session_ctx),
      do: is?(session, :session) and is?(role, :role)

    def is?({:map, map}, :maty_actor_state) do
      has_all_keys? = Map.has_key?(map, :sessions) and Map.has_key?(map, :callbacks)

      cond do
        not has_all_keys? ->
          false

        true ->
          %{sessions: {:map, session_map}, callbacks: {:map, callback_map}} = map

          s_valid? =
            session_map
            |> Map.to_list()
            |> Enum.all?(fn {k, v} -> is?(k, :session_id) and is?(v, :session) end)

          c_valid? =
            callback_map
            |> Map.to_list()
            |> Enum.all?(fn {k, v} ->
              is?(k, :init_token) and v == {:tuple, [T.role(), :function]}
            end)

          s_valid? and c_valid?
      end
    end

    def is?({:tuple, [:atom, :atom, state]}, :suspend),
      do: is?(state, :maty_actor_state)

    def is?({:tuple, [:atom, :atom, state]}, :done), do: is?(state, :maty_actor_state)

    def is?(_, _), do: false
  end
end
