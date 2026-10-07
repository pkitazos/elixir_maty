defmodule Maty.Types do
  @moduledoc """
  Custom types used in Maty.
  """

  alias Maty.Types.T

  @type session_id :: reference()
  @type init_token :: reference()
  @type role :: atom()
  @type handler_label :: atom()

  # todo: this should be tightened a bit more than `any()`
  @type message :: {atom(), any()}

  @type session :: Maty.Session.t()

  # this is a custom wrapper type
  # a particular handler always needs some session context
  # that is, the actual session, and the role of the actor for the given handler
  @type session_ctx :: {session(), role()}

  @type maty_actor_state :: Maty.DSL.State.t()

  @type candidate :: {pid(), init_token()}
  # an access point holds a map of candidate participants
  # it maps roles to queues storing pairs of `PID` * `REF` (initialisation token)
  @type access_point_state :: %{role() => :queue.queue(candidate())}

  # this maps our type names to their actual structural type
  def map do
    %{
      session_id: T.session_id(),
      init_token: T.init_token(),
      role: T.role(),
      session: T.session(),
      session_ctx: T.session_ctx(),
      maty_actor_state: T.maty_actor_state()
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
    def handler_label, do: :atom

    def message, do: {:tuple, [:atom, :any]}

    def session,
      do:
        {:map,
         %{
           id: T.session_id(),
           handlers: {:map, %{T.role() => {:tuple, [T.handler_label(), T.role()]}}},
           participants: {:map, %{T.role() => :pid}},
           # todo: see if I can make this a little nicer..
           local_state: :any
         }}

    def session_ctx, do: {:tuple, [T.session(), T.role()]}

    def maty_actor_state,
      do:
        {:map,
         %{
           sessions: {:map, %{T.session_id() => T.session()}},
           callbacks: {:map, %{T.init_token() => {:tuple, [T.role(), T.handler_label(), :any]}}}
         }}
  end
end
