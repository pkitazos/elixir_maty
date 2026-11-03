defmodule Maty.Typechecker.Error.ProtocolViolation do
  alias Maty.Typechecker.Error

  # todo: verify when this is returned
  #
  # I think this is currentl used when a handler is annotated with a label that
  # has no declared session type
  def missing_handler(module, handler, meta) do
    %Error{
      category: :protocol_violation,
      kind: :missing_handler,
      module: module,
      handler: handler,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  # An init handler must initiate the actors role in a session
  # if they are the first actor to send a message then the handler should send
  # otherwise the handler suspends into their first receive
  def init_handler_starts_with_receive(module, meta, handler, st) do
    %Error{
      category: :protocol_violation,
      kind: :init_handler_starts_with_receive,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      st: st
    }
  end

  # a message handler session type must begin with a receive (SIn)
  def message_handler_not_receive(module, meta, handler, st) do
    %Error{
      category: :protocol_violation,
      kind: :message_handler_not_receive,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      st: st
    }
  end

  # `got` is the MatyDSL call that was attempted, as `{action, argument_asts}`
  # todo: add `@spec`s
  def incorrect_action(module, meta, [got: {action, args} = got], st)
      when action in [:send, :suspend, :done] and is_list(args) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_action,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got},
      st: st
    }
  end

  def incorrect_recipient_participant(module, meta, handler, st,
        received: received,
        declared: declared,
        expected: expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_recipient_participant,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      details: %{received: received, declared: declared, expected: expected},
      st: st
    }
  end

  def incorrect_incoming_message_label(module, meta, handler, st,
        got: label_received,
        expected: labels_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_incoming_message_label,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      details: %{got: label_received, expected: labels_expected},
      st: st
    }
  end

  def incorrect_incoming_payload_type(module, meta, handler, st,
        got: payload_received,
        expected: payload_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_incoming_payload_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      details: %{got: payload_received, expected: payload_expected},
      st: st
    }
  end

  def incorrect_target_participant(module, meta, st,
        got: role_received,
        expected: role_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_target_participant,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: role_received, expected: role_expected},
      st: st
    }
  end

  def incorrect_handler_suspension(module, meta, st,
        got: handler_received,
        expected: handler_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_handler_suspension,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: handler_received, expected: handler_expected},
      st: st
    }
  end

  def incorrect_message_label(module, meta, st,
        got: label_received,
        expected: labels_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_message_label,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: label_received, expected: labels_expected},
      st: st
    }
  end

  def incorrect_payload_type(module, meta, st,
        got: payload_received,
        expected: payload_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_payload_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: payload_received, expected: payload_expected},
      st: st
    }
  end

  # todo: add @spec
  def incorrect_choice_implementation(module, meta, handler, missing_branches, st)
      when is_list(missing_branches) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_choice_implementation,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      handler: handler,
      details: %{missing_branches: missing_branches},
      st: st
    }
  end

  # the session type continues as `handler` (an `SName`), but no message handler of that name is defined
  def undefined_continuation_handler(module, meta, st, handler) do
    %Error{
      category: :protocol_violation,
      kind: :undefined_continuation_handler,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{handler: handler},
      st: st
    }
  end

  # suspend was given a message handler, but it implements a different session type
  # than the handler the session type names (`expected_handler`)
  def handler_session_type_mismatch(module, meta, st, expected_handler,
        got: got_st,
        expected: expected_st
      ) do
    %Error{
      category: :protocol_violation,
      kind: :handler_session_type_mismatch,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{expected_handler: expected_handler, got: got_st, expected: expected_st},
      st: st
    }
  end

  def suspend_invalid_handler_type(module, meta, [got: got], st) do
    %Error{
      category: :protocol_violation,
      kind: :suspend_invalid_handler_type,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got},
      st: st
    }
  end

  # Fired when a message-handler body finishes without terminating the session (it should reduce to ⊥ via suspend/done)
  # - `got_return` is the body's value type
  # - `st` carries the residual session type that was left unconsumed
  #
  # A message or init handler body must end with suspend or done
  # The check looks at two things, the session reached ⊥ and the body returned :no_return,
  # but both come from suspend/done, so they fail together and are one error
  def handler_body_wrong_termination(meta, handler_label, return_type, final_st) do
    %Error{
      category: :protocol_violation,
      kind: :handler_body_wrong_termination,
      handler: handler_label,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got_return: return_type},
      st: final_st
    }
  end
end
