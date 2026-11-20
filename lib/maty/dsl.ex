defmodule Maty.DSL do
  @moduledoc """
  Provides user-friendly macros for the Maty framework.

  These macros simplify the process of writing session-typed actors by providing
  a more declarative syntax for handlers and communication operations.
  """

  alias Maty.{DSL, Runtime}
  alias Maty.Typechecker.Error

  defmacro __using__(_opts) do
    quote do
      require Maty.DSL

      import Maty.DSL,
        only: [
          global_state: 1,
          local_state: 2,
          session_type: 2,
          on_start: 2,
          defhandler: 2
        ]
    end
  end

  defmacro global_state(type_ast) do
    quote do
      @global_state_type {unquote(Macro.escape(type_ast)), unquote(__CALLER__.line)}
    end
  end

  defmacro local_state(role, type_ast) do
    quote do
      @local_state_type {unquote(role), unquote(Macro.escape(type_ast)), unquote(__CALLER__.line)}
    end
  end

  defmacro session_type(role, handlers_ast) do
    module = __CALLER__.module
    line = __CALLER__.line

    case session_type_errors(module, line, role, handlers_ast) do
      [] ->
        quote do
          @session_type {unquote(role), unquote(handlers_ast), unquote(line)}
        end

      errors ->
        {:__block__, [], Enum.map(errors, &handler_error(nil, &1))}
    end
  end

  defp session_type_errors(module, line, role, handlers_ast) do
    invalid = fn reason, got ->
      Error.FrameworkUsage.invalid_session_type_declaration(module, [line: line], reason, got)
    end

    duplicate = fn handler ->
      Error.FrameworkUsage.duplicate_handler_session_type(module, [line: line], handler)
    end

    check(is_atom(role), invalid.(:role_not_literal, role)) ++
      handlers_errors(handlers_ast, invalid, duplicate)
  end

  defp handlers_errors({:%{}, _, entries} = handlers_ast, invalid, duplicate) do
    # the `|` of `%{m | k: v}`, the one map literal whose entries are not pairs
    handlers = for {handler, _st_ast} <- entries, do: handler
    # each handler named more than once is reported once
    repeated = Enum.uniq(handlers -- Enum.uniq(handlers))

    not_map_errors =
      check(length(handlers) == length(entries), invalid.(:handlers_not_map, handlers_ast))

    not_literal_errors =
      for(
        handler <- handlers,
        not is_atom(handler),
        do: invalid.(:handler_name_not_literal, handler)
      )

    duplicate_errors = Enum.map(repeated, duplicate)

    not_map_errors ++ not_literal_errors ++ duplicate_errors
  end

  defp handlers_errors(handlers_ast, invalid, _duplicate),
    do: [invalid.(:handlers_not_map, handlers_ast)]

  defp check(true, _error), do: []
  defp check(false, error), do: [error]

  defmacro on_start(pattern, do: body) do
    {clean_pattern, type_spec} = DSL.Pattern.process_init_pattern(pattern)

    quote do
      @impl true
      @spec on_start(unquote(type_spec)) :: maty_global_state()
      def on_start(unquote(clean_pattern)) do
        unquote(body)
      end
    end
  end

  # the handler kind is decided by its arity:
  # - `name(args, state)` is an init handler
  # - `name(role, message, state)` is a message handler
  defmacro defhandler(head, do: body) do
    module = __CALLER__.module
    meta = [line: __CALLER__.line]

    case head do
      {:when, _, [_call, guard]} ->
        handler_error(nil, Error.FrameworkUsage.unsupported_handler_guard(module, meta, guard))

      {handler_name, _, [pattern, state_var]} when is_atom(handler_name) ->
        init_handler_def(handler_name, pattern, state_var, body)

      {handler_name, _, [role, pattern, state_var]} when is_atom(handler_name) ->
        message_handler_def(__CALLER__, handler_name, role, pattern, state_var, body)

      _ ->
        handler_error(nil, Error.FrameworkUsage.invalid_handler_head(module, meta, head))
    end
  end

  # a misused handler generates no `def`
  # we record and report an error with the other handler annotation errors at `@before_compile`
  defp handler_error(func_id, error) do
    quote do
      @maty_handler_errors {unquote(Macro.escape(func_id)), unquote(Macro.escape(error))}
    end
  end

  defp init_handler_def(handler_name, pattern, state_var, body) do
    {clean_pattern, type_spec} = DSL.Pattern.process_init_pattern(pattern)

    build_init_handler(handler_name, clean_pattern, type_spec, state_var, body)
  end

  defp build_init_handler(handler_name, clean_pattern, type_spec, state_var, body) do
    stub_key = :"__handler_stub_#{handler_name}__"

    quote do
      @maty_kind {:handler, :init}
      @spec unquote(handler_name)(
              unquote(type_spec),
              maty_actor_state(),
              maty_session_ctx()
            ) :: no_return()
      # no_return() describes the body as the typechecker sees it (it always ends in suspend/done),
      # the generated function itself returns the caught {:suspend, ...} / {:done, ...} result
      def unquote(handler_name)(
            unquote(clean_pattern),
            unquote(state_var),
            var!(session_ctx, Maty.DSL)
          ) do
        unquote(catch_handler_result(body))
      end

      if not Module.has_attribute?(__MODULE__, unquote(stub_key)) do
        Module.put_attribute(__MODULE__, unquote(stub_key), true)
        @maty_kind :handler_stub
        def unquote(handler_name)(_, _), do: raise("handlers cannot be called directly")
      end
    end
  end

  defp message_handler_def(caller, handler_name, role, pattern, state_var, body) do
    func_id = {handler_name, 4}
    meta = [line: caller.line]

    with {:role, true} <- {:role, is_atom(role)},
         {:message, {tag, _payload}} when is_atom(tag) <- {:message, pattern} do
      build_message_handler(handler_name, role, pattern, state_var, body)
    else
      {:role, _} ->
        handler_error(
          func_id,
          Error.FrameworkUsage.handler_role_not_literal(caller.module, meta, role)
        )

      {:message, _} ->
        handler_error(
          func_id,
          Error.FrameworkUsage.handler_message_not_tagged_tuple(caller.module, meta, pattern)
        )
    end
  end

  defp build_message_handler(handler_name, role, pattern, state_var, body) do
    # a handler may be defined by several clauses, but its expected role only needs
    # registering once, a second identical clause would never match (and would warn)
    expects_key = :"__handler_expects_#{handler_name}__"

    quote do
      @maty_kind {:handler, :message}
      # the payload types come from the session type, so a message handler has no spec
      def unquote(handler_name)(
            unquote(role),
            unquote(pattern),
            unquote(state_var),
            var!(session_ctx, Maty.DSL)
          ) do
        unquote(catch_handler_result(body))
      end

      if not Module.has_attribute?(__MODULE__, unquote(expects_key)) do
        Module.put_attribute(__MODULE__, unquote(expects_key), true)
        def __handler_expects__(unquote(handler_name)), do: unquote(role)
        @maty_kind :handler_stub
        def unquote(handler_name)(_, _, _), do: raise("handlers cannot be called directly")
      end
    end
  end

  defp catch_handler_result(body) do
    quote do
      try do
        unquote(body)
      catch
        {:maty_suspend, next_handler, new_state} -> {:suspend, next_handler, new_state}
        {:maty_done, new_state} -> {:done, new_state}
      end
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
    - `handler`: The init handler to be called when the session starts, as a capture, e.g. `&install/2`
    - `args`: The single value passed to the init handler (use a tuple for several values, and `nil` for none).

  ## Returns
    - `{:ok, updated_state}`.
  """
  defmacro register(ap_pid, role, handler_ast, args) do
    quote do
      Runtime.register(
        unquote(ap_pid),
        unquote(role),
        unquote(handler_ast),
        unquote(args)
      )
    end
  end

  defmacro send_to(recipient, message) do
    quote do
      Runtime.send_session_message(
        var!(session_ctx, Maty.DSL),
        unquote(recipient),
        unquote(message)
      )
    end
  end

  defmacro suspend(next_handler_ast, state) do
    quote do
      Runtime.suspend(unquote(next_handler_ast), unquote(state))
    end
  end

  defmacro done(state) do
    quote do
      Runtime.done(unquote(state))
    end
  end
end
