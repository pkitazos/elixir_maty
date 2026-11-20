defmodule Maty.Types do
  @moduledoc """
  Custom types used in Maty.
  """

  alias Maty.Types.T

  @type session_id :: reference()
  @type init_token :: reference()
  @type role :: atom()
  @type handler_label :: atom()
  @type init_handler :: (term(), maty_actor_state() -> no_return())
  @type message_handler :: (role(), message(), maty_actor_state() -> no_return())

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
          args: term()
        }

  @type address_book :: %{role() => pid()}

  @type candidate :: {pid(), init_token()}
  # an access point holds a map of candidate participants
  # it maps roles to queues storing pairs of `PID` * `REF` (initialisation token)
  @type access_point_state :: %{role() => :queue.queue(candidate())}

  # List of accepted types in session types
  @supported_payload_types [
    :atom,
    :binary,
    :boolean,
    :number,
    nil,
    # maybe not these actually
    :pid,
    :ref
  ]

  @doc """
  Returns a list of all accepted types, including :number, :atom, ...
  """
  # todo: rename
  @spec payload_types :: [T.c()]
  def payload_types(), do: @supported_payload_types

  @spec is_base_type?(T.t()) :: boolean()
  def is_base_type?(t), do: t in @supported_payload_types

  defguard is_label(t) when is_atom(t) and not is_boolean(t) and not is_nil(t)

  defmodule T do
    @type c ::
            :atom
            # todo: figure out what to do when we add tagged sums
            | :boolean
            | nil
            | :number
            | :binary
            # todo: make it explicit what string operations are supported
            | :pid
            # todo: check to what degree I can actually work with PIDs and REFs
            # and make the allowed ops explicit somewhere
            | :ref

    @typedoc """
    Represents types that are supported by the Maty typechecker.
    These are primitive types that can be checked directly.
    """
    @type t ::
            c()
            | :no_return
            # ^ this is a special value
            | {:tuple, [t()]}
            | {:list, t()}
            | {:map_record, %{atom() => t()}}
            | {:map_dict, {c(), t()}}
            | {:function, [t()], t()}
            # really these should be S?
            | {:handler, :message, Maty.Types.role(), Maty.ST.t()}
            # and S! | h
            # but we don't have unions for this one..
            # also need to probably add the state type in here
            | {:handler, :init, Maty.Types.role(), t(), Maty.ST.t()}

    def role, do: :atom

    # opaque: users never look inside a session, they only pass the session context along, only needed to type `session_ctx`
    def session, do: :any

    def session_ctx, do: {:tuple, [T.session(), T.role()]}

    def local_state, do: :any
    def global_state, do: :any

    def maty_actor_state, do: {:map_record, %{local: T.local_state(), global: T.global_state()}}
  end
end
