defmodule Maty.Typechecker.Error.FrameworkUsage do
  alias Maty.Typechecker.Error

  def no_native_send(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :no_native_send,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def no_native_receive(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :no_native_receive,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def unsupported_anonymous_function(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_anonymous_function,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  # bitstring syntax other than string concatenation and interpolation was used
  def unsupported_bitstring(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_bitstring,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  # an expression that no typing rule covers (an unknown remote call, an operator without a rule, ...)
  def unsupported_expression(module, meta, ast) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_expression,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{ast: ast}
    }
  end

  # a pattern that no pattern rule covers (e.g. a case clause with a guard)
  def unsupported_pattern(module, meta, ast) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_pattern,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{ast: ast}
    }
  end

  # `&&` / `||`, which treat any value as a boolean; `and` / `or` are supported instead
  def unsupported_truthy_operator(module, meta, op) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_truthy_operator,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{op: op}
    }
  end

  def missing_session_registration(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :missing_session_registration,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def on_link_altered_session_state(module, meta, got_st) do
    %Error{
      category: :framework_usage,
      kind: :on_link_altered_session_state,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_st}
    }
  end

  def on_link_bad_return(module, meta, got) do
    %Error{
      category: :framework_usage,
      kind: :on_link_bad_return,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # `use Maty.Actor` declared roles that are not roles of the given protocol
  def unknown_roles(module, meta, protocol, unknown_roles, protocol_roles) do
    %Error{
      category: :framework_usage,
      kind: :unknown_roles,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{protocol: protocol, got: unknown_roles, known: protocol_roles}
    }
  end

  # the actor has no `global_state` declaration
  def missing_global_state(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :missing_global_state,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  # some roles the actor plays have no `local_state` declaration
  def missing_local_states(module, meta, roles) do
    %Error{
      category: :framework_usage,
      kind: :missing_local_states,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{roles: roles}
    }
  end

  # a second `global_state`, or a second `local_state` for the same role
  # `state` is `:global` or `{:local, role}`
  # todo: make this accept all duplicates as a param rather than making a new error for every duplication
  def duplicate_state_declaration(module, meta, state) do
    %Error{
      category: :framework_usage,
      kind: :duplicate_state_declaration,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{state: state}
    }
  end

  # `local_state` was given a role not in this module's `use Maty.Actor`
  def local_state_undeclared_role(module, meta, role, declared_roles) do
    %Error{
      category: :framework_usage,
      kind: :local_state_undeclared_role,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: role, known: declared_roles}
    }
  end

  # register was given an expression for the role, not a literal atom
  def role_not_literal(module, meta, got_ast) do
    %Error{
      category: :framework_usage,
      kind: :role_not_literal,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_ast}
    }
  end

  # register was given a role not in the protocol
  def undeclared_role(module, meta, role, declared_roles) do
    %Error{
      category: :framework_usage,
      kind: :undeclared_role,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: role, known: declared_roles}
    }
  end

  # defhandler was given a head with a guard
  def unsupported_handler_guard(module, meta, guard_ast) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_handler_guard,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: guard_ast}
    }
  end

  # defhandler was given a head that is neither `name(args, state)` nor `name(role, message, state)`
  def invalid_handler_head(module, meta, head_ast) do
    %Error{
      category: :framework_usage,
      kind: :invalid_handler_head,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: head_ast}
    }
  end

  # a message handler was given an expression for its role, not a literal atom
  def handler_role_not_literal(module, meta, got_ast) do
    %Error{
      category: :framework_usage,
      kind: :handler_role_not_literal,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_ast}
    }
  end

  # a function that is not a handler has the same name as a handler
  def handler_name_clash(module, meta, func_id, handler_kind)
      when handler_kind in [:init, :message] do
    %Error{
      category: :framework_usage,
      kind: :handler_name_clash,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{function: func_id, handler_kind: handler_kind}
    }
  end

  # a clause of an init handler takes a different argument type than the handler's first clause
  def init_handler_arg_type_mismatch(module, meta, handler, expected: expected, got: got) do
    %Error{
      category: :framework_usage,
      kind: :init_handler_arg_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{handler: handler, expected: expected, got: got}
    }
  end

  # a capture of something other than a handler (only handlers are first class for now)
  def unsupported_capture(module, meta, capture_ast) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_capture,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: capture_ast}
    }
  end

  # register / suspend was given `&name/n` with the wrong arity:
  # init handlers are referenced with arity 2, message handlers with arity 3
  def handler_ref_wrong_arity(module, meta, name, got, expected) do
    %Error{
      category: :framework_usage,
      kind: :handler_ref_wrong_arity,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{name: name, got: got, expected: expected}
    }
  end

  # a message handler was given a message pattern that is not `{:label, payload}`
  def handler_message_not_tagged_tuple(module, meta, got_ast) do
    %Error{
      category: :framework_usage,
      kind: :handler_message_not_tagged_tuple,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_ast}
    }
  end
end
