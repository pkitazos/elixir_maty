defmodule Maty.Actor do
  @moduledoc """
  An actor can have multiple roles in different or even in the same session
  at any point in time an actor has suspended with a handler that is able to process the next message in the session for a given role
  that is why an actor keeps an internal state at runtime which maps session IDs to another map which maps roles to handler
  For any given session * role pair, an actor only has one valid handler and one valid continuation.

  The BEAM is not really designed with this in mind, so actors only really have a single mailbox which just interleaves all messages
  from all sessions. The runtime _does_ guarantee that messages from a given process will arrive in order in another process' mailbox
  but that's about it. The Maty runtime allows us to reorder messages in the mailbox keeping the relative order between participant messages
  the same, which essentially gives us the power to reason about our mailbox as a set of mailboxes indexed by a session

  To emulate this behaviour, a Maty actor keeps an internal stash which acts in the same way (ish).
  An actor is constantly looping over the stash and its mailbox trying to process messages.
  A message from another Maty actor always arrives as a `Maty.Runtime.Envelope`, which carries the
  session it belongs to, the role it is addressed to and the role it is sent from.

  As explained above, to identify what message can currently be processed according to the session type,
  we need to look at our suspended handlers, and to do that we need the `session_id` and `to` from a given message.
  The `handlers` map will return an expected role and if the `from` of the message we're currently inspecting matches,
  then we process this message.

  ## Options

  `use Maty.Actor` requires two options:

    - `protocol`: the protocol module (implementing `Maty.Protocol`) whose sessions this actor takes part in
    - `roles`: the roles of that protocol this actor plays

  Every `MatyDSL.register/5` call in the actor must be given one of these roles as a literal atom.

      defmodule TwoBuyer.Participants.Seller do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]
        ...
      end
  """

  @callback on_start(args :: term()) :: {:ok, global_state :: term()}

  defmacro __using__(opts) do
    protocol = Keyword.fetch!(opts, :protocol)
    roles = Keyword.fetch!(opts, :roles)

    quote do
      @maty_protocol unquote(protocol)
      @maty_roles unquote(roles)
      use Maty.Hook
      use Maty.DSL
      import ST.Sigils
      require Maty.DSL
      require Maty.Runtime.InternalState
      @behaviour Maty.Actor

      def start_link(args) do
        Maty.Actor.start_link(__MODULE__, args)
      end
    end
  end

  @spec start_link(module(), any()) :: {:ok, pid()}
  def start_link(module, args) do
    pid = spawn_link(fn -> Maty.Runtime.init_and_run(module, args) end)
    {:ok, pid}
  end
end
