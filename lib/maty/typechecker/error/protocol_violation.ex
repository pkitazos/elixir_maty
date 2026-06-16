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
  def init_handler_starts_with_receive(module, handler, st) do
    %Error{
      category: :protocol_violation,
      kind: :init_handler_starts_with_receive,
      module: module,
      handler: handler,
      st: st
    }
  end

  # a message handler session type must begin with a receive (SIn)
  def message_handler_not_receive(module, handler, st) do
    %Error{
      category: :protocol_violation,
      kind: :message_handler_not_receive,
      module: module,
      handler: handler,
      st: st
    }
  end

  def incorrect_action(module, meta, [got: got], st) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_action,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got},
      st: st
    }
  end

  def incorrect_recipient_participant(module, handler, st,
        got: role_received,
        expected: role_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_recipient_participant,
      module: module,
      handler: handler,
      details: %{got: role_received, expected: role_expected},
      st: st
    }
  end

  def incorrect_incoming_message_label(module, handler, st,
        got: label_received,
        expected: labels_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_incoming_message_label,
      module: module,
      handler: handler,
      details: %{got: label_received, expected: labels_expected},
      st: st
    }
  end

  def incorrect_incoming_payload_type(module, handler, st,
        got: payload_received,
        expected: payload_expected
      ) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_incoming_payload_type,
      module: module,
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

  def incorrect_choice_implementation(module, handler, missing_branches, st) do
    %Error{
      category: :protocol_violation,
      kind: :incorrect_choice_implementation,
      module: module,
      handler: handler,
      details: %{missing_branches: missing_branches},
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

  # Fired by Helpers.check_st_unchanged/3 when the scrutinee of a `case` (or any
  # expression required to be pure) advances the session type. `from`/`to` are
  # the session types before and after, carried so the Formatter can repr them.
  #
  # todo: deprecate - I think it's actually kinda weird that I don't let all
  # expressions happen in all contexts. I guess it doesn't really make too much
  # sense to try and pattern match on a send result, since it always returns :ok
  # but that's the user's problem
  def case_scrutinee_altered_state(meta, from: from, to: to) do
    %Error{
      category: :protocol_violation,
      kind: :case_scrutinee_altered_state,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{from: from, to: to}
    }
  end

  # Fired when a message-handler body finishes without terminating the session
  # (it should reduce to ⊥ via suspend/done). `got_return` is the body's value
  # type; `st` carries the residual session type that was left unconsumed.
  #
  # MATY_ERROR_KIND_REVIEW
  # this currently conflates two failures: (1) final_st ≠ ⊥, the session wasn't
  # consumed, and (2) return_type ≠ :no_return, the body returned a value instead
  # of yielding via suspend/done
  #
  # todo: (2) is arguably a :framework_usage shape rule
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
