defmodule Maty.DSL do
  alias Maty.{DSL, Runtime}

  defmacro __using__(_opts) do
    quote do
      require Maty.DSL
      import Maty.DSL, only: [on_start: 2, init_handler: 4, handler: 5]
    end
  end

  @moduledoc """
  Provides user-friendly macros for the Maty framework.

  These macros simplify the process of writing session-typed actors by providing
  a more declarative syntax for handlers and communication operations.
  """

  defmacro on_start(pattern, do: body) do
    {clean_pattern, type_spec} = DSL.Pattern.process_init_pattern(pattern)

    quote do
      @impl true
      @spec on_start(unquote(type_spec)) :: {:ok, global_state()}
      #   somehow type the global state from this ^
      def on_start(unquote(clean_pattern)) do
        unquote(body)
      end
    end
  end

  defmacro init_handler(handler_name, pattern, state_var, do: body) do
    {clean_pattern, type_spec} = DSL.Pattern.process_init_pattern(pattern)

    quote do
      @init_handler unquote(handler_name)
      @spec unquote(handler_name)(
              unquote(type_spec),
              maty_actor_state(),
              session_ctx()
            ) :: no_return()
      # no_return() describes the body as the typechecker sees it (it always ends in suspend/done),
      # the generated function itself returns the caught {:suspend, ...} / {:done, ...} result
      def unquote(handler_name)(
            unquote(clean_pattern),
            unquote(state_var),
            session_ctx
          ) do
        try do
          var!(session_ctx) = session_ctx

          # use the session_ctx variable so the LSP won't yell at me
          _ = var!(session_ctx)
          unquote(body)
        catch
          {:maty_suspend, next_handler, new_state} -> {:suspend, next_handler, new_state}
          {:maty_done, new_state} -> {:done, new_state}
        end
      end
    end
  end

  defmacro handler(
             handler_name,
             role,
             pattern,
             state_var,
             do: body
           ) do
    # first verify we have a proper tagged tuple pattern
    # the pattern should be a 2-tuple with an atom tag as the first element
    case pattern do
      {tag, _payload} when is_atom(tag) ->
        # process the pattern to extract the cleaned pattern and type specification
        {clean_pattern, type_spec} = DSL.Pattern.process_pattern(pattern)

        # a handler may be defined by several clauses, but its expected role only needs
        # registering once, a second identical clause would never match (and would warn)
        expects_key = :"__handler_expects_#{handler_name}__"

        quote do
          @handler unquote(handler_name)
          # no_return() describes the body as the typechecker sees it (it always ends in suspend/done),
          # the generated function itself returns the caught {:suspend, ...} / {:done, ...} result
          @spec unquote(handler_name)(
                  unquote(role),
                  unquote(type_spec),
                  maty_actor_state(),
                  session_ctx()
                ) :: no_return()
          def unquote(handler_name)(
                unquote(role),
                unquote(clean_pattern),
                unquote(state_var),
                session_ctx
              ) do
            try do
              var!(session_ctx) = session_ctx

              # use the session_ctx variable so the LSP won't yell at me
              _ = var!(session_ctx)
              unquote(body)
            catch
              {:maty_suspend, next_handler, new_state} -> {:suspend, next_handler, new_state}
              {:maty_done, new_state} -> {:done, new_state}
            end
          end

          if not Module.has_attribute?(__MODULE__, unquote(expects_key)) do
            Module.put_attribute(__MODULE__, unquote(expects_key), true)
            def __handler_expects__(unquote(handler_name)), do: unquote(role)
          end
        end

      _ ->
        # ERROR: Expected a tagged tuple pattern like {:tag, payload}
        # for now, we'll just raise a compile-time error
        raise ArgumentError, "Expected a tagged tuple pattern like {:tag, payload}"
    end
  end

  @doc """
  Registers an actor instance with the Access Point (AP).

  This function sends a registration message to the AP and stores
  initialisation information (role, handler name, initial arguments)
  in the actor's state, associated with a unique token.

  The handler name and its arguments together stand in for the callback closure of the Maty calculus
  when the session starts, the init handler is called with: `args`, the actor state and the session context.

  ## Parameters
    - `ap_pid`: The PID of the Access Point process.
    - `role`: The role this actor will play in the session (atom).
    - `handler`: The name of the `init_handler` to be called when the session starts, as a literal atom
    - `args`: The single value passed to the `init_handler` (use a tuple for several values, and `nil` for none).
    - `state`: The current actor state (`maty_actor_state`).

  ## Returns
    - `{:ok, updated_state}`.
  """
  defmacro register(ap_pid, role, handler, args, initial_session_role_state) do
    quote do
      Runtime.register(
        unquote(ap_pid),
        unquote(role),
        unquote(handler),
        unquote(args),
        unquote(initial_session_role_state)
      )
    end
  end

  defmacro send(recipient, message) do
    quote do
      Runtime.send_session_message(var!(session_ctx), unquote(recipient), unquote(message))
    end
  end

  defmacro suspend(next_handler, state) do
    quote do
      Runtime.suspend(unquote(next_handler), unquote(state))
    end
  end

  defmacro done(state) do
    quote do
      Runtime.done(unquote(state))
    end
  end
end
