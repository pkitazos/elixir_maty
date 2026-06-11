defmodule Maty.Typechecker.Error.Formatter do
  @moduledoc """
  Renders a `%Maty.Typechecker.Error{}` struct into the human-readable text
  reported at compile time.
  """

  alias Maty.Typechecker.Error

  @spec format(Error.t()) :: String.t()
  def format(%Error{} = error) do
    render(error) <> render_trace(error.trace)
  end

  # --- :protocol_violation

  defp render(%Error{category: :protocol_violation, kind: :incorrect_action} = e) do
    %{got: got} = e.details
    actions = Maty.ST.get_action(e.st)

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Action
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Tried: #{got}
      Current permitted actions: #{actions}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  # todo: add line
  defp render(%Error{category: :protocol_violation, kind: :incorrect_recipient_participant} = e) do
    %{got: role_received, expected: role_expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Participant
      Module: #{e.module}
      Handler: #{e.handler}
      --
      Got: #{render_atom(role_received)}
      Expected: #{render_atom(role_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  # todo: add line
  defp render(%Error{category: :protocol_violation, kind: :incorrect_incoming_message_label} = e) do
    %{got: label_received, expected: labels_expected} = e.details
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Message Label
      Module: #{e.module}
      Handler: #{e.handler}
      --
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  # todo: add line
  defp render(%Error{category: :protocol_violation, kind: :incorrect_incoming_payload_type} = e) do
    %{got: payload_received, expected: payload_expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Payload Type
      Module: #{e.module}
      Handler: #{e.handler}
      --
      Got: #{render_atom(payload_received)}
      Expected: #{render_atom(payload_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_target_participant} = e) do
    %{got: role_received, expected: role_expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Target Participant
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Got: #{render_atom(role_received)}
      Expected: #{render_atom(role_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_handler_suspension} = e) do
    %{got: handler_received, expected: handler_expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Handler Suspension
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Got: #{render_atom(handler_received)}
      Expected: #{render_atom(handler_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_message_label} = e) do
    %{got: label_received, expected: labels_expected} = e.details
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Message Label
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_payload_type} = e) do
    %{got: payload_received, expected: payload_expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Payload Type
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Got: #{render_atom(payload_received)}
      Expected: #{render_atom(payload_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  # todo: add line
  defp render(%Error{category: :protocol_violation, kind: :incorrect_choice_implementation} = e) do
    %{missing_branches: missing_branches} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Incomplete Message Handler Implementation
      Module: #{e.module}
      Handler: #{e.handler}
      --
      Missing implementation for branches: #{missing_branches}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :suspend_invalid_handler_type} = e) do
    %{got: got} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Suspended with Invalid Handler
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Tried: #{got}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  # todo: deprecate
  defp render(%Error{category: :protocol_violation, kind: :case_scrutinee_altered_state} = e) do
    %{from: from, to: to} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Case Scrutinee Altered Session State
      Line: #{e.meta[:line]}
      --
      The scrutinee of a case expression must not perform any session actions.
      Before: #{Maty.ST.repr(from)}
      After: #{Maty.ST.repr(to)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :handler_body_wrong_termination} = e) do
    %{got_return: got_return} = e.details

    """
    \n\n** (ElixirMatyTypeError) Protocol Violation: Handler Did Not Terminate the Session
      Handler: #{e.handler}
      Line: #{e.meta[:line]}
      --
      A message handler must end by suspending or completing the session.
      Returned: #{render_atom(got_return)}
      Remaining session type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: category, kind: kind}) do
    # todo: eventually kill this
    raise ArgumentError,
          "no Formatter clause for error kind #{inspect({category, kind})} — " <>
            "add a render/1 clause when migrating this constructor"
  end

  defp render_trace([]), do: ""

  defp render_trace(frames) do
    lines = Enum.map_join(frames, "\n", &("    " <> render_frame(&1)))
    "  Trace:\n" <> lines <> "\n"
  end

  defp render_frame({:call, {f, a}, meta}), do: "via #{f}/#{a}#{render_line(meta)}"
  defp render_frame({:clause, {f, a}, index}), do: "in clause ##{index} of #{f}/#{a}"

  defp render_frame({:case_branch, index, meta}),
    do: "in case branch ##{index}#{render_line(meta)}"

  defp render_line(meta) do
    case Keyword.get(meta, :line) do
      nil -> ""
      line -> " (line #{line})"
    end
  end

  defp render_atom(elt) when is_atom(elt), do: ":#{elt}"
  defp render_atom(elt), do: "#{inspect(elt)}"
end
