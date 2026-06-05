defmodule Maty.Typechecker.Error.ProtocolViolation do
  alias Maty.ST

  defp render_atom(elt) when is_atom(elt), do: ":#{elt}"
  defp render_atom(elt), do: "#{inspect(elt)}"

  def incorrect_action(module, meta, [got: got], st) do
    line = Keyword.fetch!(meta, :line)
    actions = ST.get_action(st)

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Action
      Module: #{module}
      Line: #{line}
      --
      Tried: #{got}
      Current permitted actions: #{actions}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_recipient_participant(module, handler, st,
        got: role_received,
        expected: role_expected
      ) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Participant
      Module: #{module}
      Handler: #{handler}
      --
      Got: #{render_atom(role_received)}
      Expected: #{render_atom(role_expected)}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_incoming_message_label(module, handler, st,
        got: label_received,
        expected: labels_expected
      ) do
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Message Label
      Module: #{module}
      Handler: #{handler}
      --
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_incoming_payload_type(module, handler, st,
        got: payload_received,
        expected: payload_expected
      ) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Payload Type
      Module: #{module}
      Handler: #{handler}
      --
      Got: #{render_atom(payload_received)}
      Expected: #{render_atom(payload_expected)}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_target_participant(module, [{:line, line} | _], st,
        got: role_received,
        expected: role_expected
      ) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Target Participant
      Module: #{module}
      Line: #{line}
      --
      Got: #{render_atom(role_received)}
      Expected: #{render_atom(role_expected)}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_handler_suspension(module, [{:line, line} | _], st,
        got: handler_received,
        expected: handler_expected
      ) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Handler Suspension
      Module: #{module}
      Line: #{line}
      --
      Got: #{render_atom(handler_received)}
      Expected: #{render_atom(handler_expected)}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_message_label(module, [{:line, line} | _], st,
        got: label_received,
        expected: labels_expected
      ) do
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Message Label
      Module: #{module}
      Line: #{line}
      --
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_payload_type(module, [{:line, line} | _], st,
        got: payload_received,
        expected: payload_expected
      ) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Payload Type
      Module: #{module}
      Line: #{line}
      --
      Got: #{render_atom(payload_received)}
      Expected: #{render_atom(payload_expected)}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def incorrect_choice_implementation(module, handler, missing_branches, st) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incomplete Message Handler Implementation
      Module: #{module}
      Handler: #{handler}
      --
      Missing implementation for branches: #{missing_branches}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def suspend_invalid_handler_type(module, [{:line, line} | _], [got: got], st) do
    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Suspended with Invalid Handler
      Module: #{module}
      Line: #{line}
      --
      Tried: #{got}
      --
      Session Type: #{ST.repr(st)}
    """
  end

  def send_invalid_state(module, meta, [got: got], st) do
    line = Keyword.fetch!(meta, :line)

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Action
      Module: #{module}
      Line: #{line}
      --
      Tried: #{got}
      --
      Session Type: #{ST.repr(st)}
    """
  end
end
