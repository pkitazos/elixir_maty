defmodule Maty.Typechecker.Error.Formatter do
  @moduledoc """
  Renders a `%Maty.Typechecker.Error{}` struct into the human-readable text
  reported at compile time.
  """

  alias Maty.Typechecker.Error
  alias Maty.Utils

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

  # --- :type_mismatch

  defp render(%Error{category: :type_mismatch, kind: :logical_operator_requires_boolean} = e) do
    %{operator: operator, operand_type: operand_type} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Logical Operator Type Error
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Operator: #{render_operator(operator)}
      Expected operand type: :boolean
      Got operand type: #{render_type(operand_type)}
      --
      Logical operators require boolean operands.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :return_type_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Return Type Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Expected return type: #{render_type(expected)}
      Got return type: #{render_type(got)}
      --
      The function's actual return type does not match the declared return type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :binary_operator_type_mismatch} = e) do
    %{operator: operator, lhs: lhs_type, rhs: rhs_type} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Binary Operator Type Error
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Operator: #{render_operator(operator)}
      Left operand type: #{render_type(lhs_type)}
      Right operand type: #{render_type(rhs_type)}
      --
      The operand types are not compatible with this binary operator.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :logical_operator_type_mismatch} = e) do
    %{operator: operator, lhs: lhs_type, rhs: rhs_type} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Logical Operator Type Error
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Operator: #{render_operator(operator)}
      Left operand type: #{render_type(lhs_type)}
      Right operand type: #{render_type(rhs_type)}
      Expected operand types: :boolean and :boolean
      --
      Logical operators require both operands to be boolean.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :list_elements_incompatible} = e) do
    %{element_types: element_types} = e.details
    formatted_types = element_types |> Enum.map(&render_type/1) |> Enum.join(", ")

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Incompatible List Elements
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Element types found: #{formatted_types}
      --
      All elements in a list must have the same type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :case_branches_incompatible} = e) do
    %{branches: branches} = e.details

    type_lines =
      if Keyword.has_key?(branches, :t1) do
        [
          "Types Incompatible:",
          "  Branch type 1: #{render_type(branches[:t1])}",
          "  Branch type 2: #{render_type(branches[:t2])}"
        ]
      else
        []
      end

    # idk if this works tbh
    indent = if length(type_lines) == 0, do: "", else: "  "

    session_lines =
      if Keyword.has_key?(branches, :q1) do
        [
          "#{indent}Session Types Incompatible:",
          "  Branch session state 1: #{inspect(branches[:q1])}",
          "  Branch session state 2: #{inspect(branches[:q2])}"
        ]
      else
        []
      end

    lines = Enum.join(type_lines ++ session_lines, "\n")

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Incompatible Case Branches
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
    #{lines}
      --
      All case branches must return the same type and result in compatible session states.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :invalid_maty_state_type} = e) do
    %{internal: %Error.Internal{title: title, opts: opts, message: message}} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: #{title}
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      #{opts}
      --
      #{message}
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :send_message_not_tuple} = e) do
    %{got: message_ast} = e.details

    """
    \n\n** (ElixirMatyTypeError) Type Mismatch Error: Send Message Not Tuple
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Expected: Tagged tuple message {label, payload}
      Got: #{inspect(message_ast)}
      --
      Messages must be 2-tuples with an atom label and payload.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :conflicting_pattern_bindings} = e) do
    %{conflicting_vars: conflicting_vars} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Conflicting Pattern Bindings
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Conflicting variables: #{conflicting_vars}
      --
      The same variable is bound multiple times in this pattern, which is not allowed.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_type_mismatch} = e) do
    %{pattern: pattern, expected: expected, got: got} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Pattern Type Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Pattern: #{render_pattern(pattern)}
      Expected type: #{render_type(expected)}
      Got type: #{render_type(got)}
      --
      The pattern does not match the expected type.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_arity_mismatch} = e) do
    %{pattern_type: pattern_type, expected: expected, got: got} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Pattern Arity Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Pattern type: #{pattern_type}
      Expected arity: #{expected}
      Got arity: #{got}
      --
      The pattern has a different number of elements than expected.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :tuple_arity_mismatch} = e) do
    %{pattern_arity: pattern_arity, expected: expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Tuple Arity Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Pattern: #{pattern_arity}-tuple
      Expected: #{expected}-tuple
      --
      The tuple pattern has #{pattern_arity} elements but expected #{expected} elements.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_not_tuple} = e) do
    %{got: got} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Pattern Type Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Pattern: 2-tuple
      Expected: tuple
      Got: #{render_type(got)}
      --
      Expected a tuple but got a different type.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :complex_map_key} = e) do
    %{key_ast: key_ast} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Complex Map Key
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Key expression: #{inspect(key_ast)}
      --
      Map patterns require literal atom keys. Complex expressions are not allowed as map keys.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :invalid_map_key_type} = e) do
    %{got: got, expected: expected} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Invalid Map Key Type
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Expected key type: #{render_type(expected)}
      Got key type: #{render_type(got)}
      --
      Map pattern keys must be atoms.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_map_key_not_found} = e) do
    %{missing_key: missing_key} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Map Key Not Found
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Missing key: #{render_pattern(missing_key)}
      --
      The pattern references a map key that is not present in the expected map type.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_map_key_not_atom} = e) do
    %{key_ast: key_ast} = e.details

    """
    \n\n** (ElixirMatyTypeError) Pattern Matching Error: Map Key Not Atom
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Key expression: #{inspect(key_ast)}
      --
      Map pattern keys must be literal atoms.
    """
  end

  # --- :function_call

  defp render(%Error{category: :function_call, kind: :function_not_exist} = e) do
    %{func_id: func_id} = e.details
    func_str = Utils.to_func(func_id)

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: Function Does Not Exist
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Function: #{func_str}
      --
      The function #{func_str} is not defined in this module.
    """
  end

  defp render(%Error{category: :function_call, kind: :arity_mismatch} = e) do
    %{func_id: func_id, expected: expected, got: got} = e.details
    func_str = Utils.to_func(func_id)

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: Arity Mismatch
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Function: #{func_str}
      Expected arity: #{expected}
      Got arity: #{got}
      --
      Arity mismatch between function spec and function definition.
    """
  end

  defp render(%Error{category: :function_call, kind: :no_matching_function_clause} = e) do
    %{func_id: func_id, arg_types: arg_types} = e.details
    func_str = Utils.to_func(func_id)
    formatted_args = arg_types |> Enum.map(&render_type/1) |> Enum.join(", ")

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: No Matching Function Clause
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Function: #{func_str}
      Called with argument types: (#{formatted_args})
      --
      No function clause matches the provided argument types.
    """
  end

  defp render(%Error{category: :function_call, kind: :function_altered_session_state} = e) do
    %{func_id: func_id, final_state: final_state} = e.details
    func_str = Utils.to_func(func_id)

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: Function Altered Session State
      Module: #{e.module}
      Line: #{e.meta[:line]}
      --
      Function: #{func_str}
      Final state: #{inspect(final_state)}
      --
      Function altered the session state when it should remain unchanged.
    """
  end

  defp render(%Error{category: :function_call, kind: :wrong_number_of_clauses} = e) do
    %{func_id: func_id, expected: expected, got: got} = e.details
    func_str = Utils.to_func(func_id)

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: Wrong Number of Clauses
      Module: #{e.module}
      Function: #{func_str}
      --
      Expected clauses: #{expected}
      Got clauses: #{got}
      --
      Incompatible number of clauses defined for function.
    """
  end

  defp render(%Error{category: :function_call, kind: :wrong_number_of_specs} = e) do
    %{func_id: func_id, expected: expected, got: got} = e.details
    func_str = Utils.to_func(func_id)

    """
    \n\n** (ElixirMatyTypeError) Function Call Error: Wrong Number of Specs
      Module: #{e.module}
      Function: #{func_str}
      --
      Expected specs: #{expected}
      Got specs: #{got}
      --
      Incompatible number of @spec annotations defined for function.
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

  defp render_pattern(pattern) when is_atom(pattern), do: ":#{pattern}"
  defp render_pattern(pattern) when is_binary(pattern), do: "\"#{pattern}\""
  defp render_pattern(pattern) when is_number(pattern), do: "#{pattern}"
  defp render_pattern(pattern) when is_boolean(pattern), do: "#{pattern}"
  defp render_pattern(nil), do: "nil"
  defp render_pattern(pattern), do: "#{inspect(pattern)}"

  defp render_type(type) when is_atom(type), do: ":#{type}"
  defp render_type(type), do: "#{inspect(type)}"

  defp render_operator(op) when is_atom(op), do: "#{op}"
  defp render_operator(op), do: "#{inspect(op)}"
end
