defmodule Maty.Types do
  @moduledoc """
  Custom types used in Maty.
  """

  alias Maty.Types.T

  @type session_id :: reference()
  @type init_token :: reference()
  @type role :: atom()
  @type handler_label :: atom()

  # placeholders / grep targets until I decide how to type local and global state
  @type local_state :: term()
  @type global_state :: term()

  # todo: this should be tightened a bit more than `any()`
  @type message :: {atom(), any()}

  @type session :: Maty.Runtime.Session.t()

  # this is a custom wrapper type
  # a particular handler always needs some session context
  # that is, the actual session, and the role of the actor for the given handler
  @type session_ctx :: {session(), role()}

  @type maty_actor_state :: %{local: local_state(), global: global_state()}

  @type handler_result ::
          {:suspend, handler_label(), maty_actor_state()} | {:done, maty_actor_state()}

  @type registration_info :: %{
          role: role(),
          init_handler: handler_label(),
          args: term(),
          local: local_state()
        }

  @type address_book :: %{role() => pid()}

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
      local_state: T.local_state(),
      global_state: T.global_state(),
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
            | :map

    def session_id, do: :ref
    def init_token, do: :ref
    def role, do: :atom
    def handler_label, do: :atom

    def message, do: {:tuple, [:atom, :any]}

    # opaque: users never look inside a session, they only pass the session context along, only needed to type `session_ctx`
    def session, do: :any

    def session_ctx, do: {:tuple, [T.session(), T.role()]}

    def local_state, do: :any
    def global_state, do: :any

    def maty_actor_state, do: {:map, %{local: T.local_state(), global: T.global_state()}}
  end
end
