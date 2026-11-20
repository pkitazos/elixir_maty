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

  # todo: potentially rename
  defp render(%Error{category: :protocol_violation, kind: :missing_handler}) do
    """
    Protocol Violation: Missing Handler
      No session type is declared for this handler's label.
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :init_handler_starts_with_receive} = e) do
    """
    Protocol Violation: Init Handler Starts With a Receive
      An init handler must initiate the session (send or suspend), but the protocol
      for this role begins by receiving. That first step needs a message handler.
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :message_handler_not_receive} = e) do
    """
    Protocol Violation: Message Handler Does Not Receive
      A message handler runs when a message is received, so its session type must
      begin with a receive. This handler's session type does not.
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_action} = e) do
    %{got: got} = e.details
    actions = Maty.ST.get_action(e.st)

    """
    Protocol Violation: Incorrect Action
      Tried: #{render_action(got)}
      Current permitted actions: #{actions}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_recipient_participant} = e) do
    %{received: received, expected: expected} = e.details

    """
    Protocol Violation: Incorrect Incoming Participant
      Received role (handler arg): #{render_atom(received)}
      Expected role (session type): #{render_atom(expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_incoming_message_label} = e) do
    %{got: label_received, expected: labels_expected} = e.details
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    Protocol Violation: Incorrect Incoming Message Label
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_target_participant} = e) do
    %{got: role_received, expected: role_expected} = e.details

    """
    Protocol Violation: Incorrect Target Participant
      Got: #{render_atom(role_received)}
      Expected: #{render_atom(role_expected)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :undefined_continuation_handler} = e) do
    %{handler: handler} = e.details

    """
    Protocol Violation: Undefined Continuation Handler
      Continues as: #{handler}
      --
      The session type continues as #{handler}, but no message handler named #{handler} is defined in this module.
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :handler_session_type_mismatch} = e) do
    %{got: got_st, expected: expected_st} = e.details

    """
    Protocol Violation: Handler for a Different Session Type
      Got: a message handler for #{Maty.ST.repr(got_st)}
      Expected: a message handler for #{Maty.ST.repr(expected_st)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :handler_role_mismatch} = e) do
    %{expected: expected_role, got: got_role} = e.details

    """
    Protocol Violation: Handler for a Different Role
      Got: a message handler for role #{render_atom(got_role)}
      Expected: a message handler for role #{render_atom(expected_role)}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_message_label} = e) do
    %{got: label_received, expected: labels_expected} = e.details
    acceptable_labels = labels_expected |> Enum.map(&render_atom/1) |> Enum.join(" | ")

    """
    Protocol Violation: Incorrect Message Label
      Got: #{render_atom(label_received)}
      Expected: #{acceptable_labels}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :incorrect_choice_implementation} = e) do
    %{missing_branches: missing_branches} = e.details

    """
    Protocol Violation: Incomplete Message Handler Implementation
      Missing implementation for branches: #{Maty.ST.repr(%{e.st | branches: missing_branches})}
      --
      Session Type: #{Maty.ST.repr(e.st)}
    """
  end

  defp render(%Error{category: :protocol_violation, kind: :handler_body_wrong_termination} = e) do
    %{got_return: got_return} = e.details

    """
    Protocol Violation: Handler Did Not Terminate the Session
      A handler must end by suspending or completing the session.
      Returned: #{render_atom(got_return)}
      Remaining session type: #{Maty.ST.repr(e.st)}
    """
  end

  # --- :type_mismatch

  defp render(%Error{category: :type_mismatch, kind: :arithmetic_operator_requires_number} = e) do
    %{operator: operator, operand_type: operand_type} = e.details

    """
    Type Mismatch Error: Arithmetic Operator Type Error
      Operator: #{render_operator(operator)}
      Expected operand type: :number
      Got operand type: #{render_type(operand_type)}
      --
      Arithmetic operators require number operands.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :logical_operator_requires_boolean} = e) do
    %{operator: operator, operand_type: operand_type} = e.details

    """
    Type Mismatch Error: Logical Operator Type Error
      Operator: #{render_operator(operator)}
      Expected operand type: :boolean
      Got operand type: #{render_type(operand_type)}
      --
      Logical operators require boolean operands.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :handler_expected} = e) do
    %{expected_kind: expected_kind, got: got} = e.details

    {title, macro, kind, arity} =
      case expected_kind do
        :init -> {"an Init Handler", "register", "an init handler", 2}
        :message -> {"a Message Handler", "suspend", "a message handler", 3}
      end

    """
    Type Mismatch Error: Expected #{title}
      Got: #{render_type(got)}
      --
      #{macro} must be given #{kind}, as a capture &name/#{arity} of one defined in this module.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :return_type_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Return Type Mismatch
      Expected return type: #{render_type(expected)}
      Got return type: #{render_type(got)}
      --
      The function's actual return type does not match the declared return type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :expected} = e) do
    %{expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Unexpected Type
      Expected: #{render_type(expected)}
      Got: #{render_type(got)}
      --
      The expression's type does not match the type expected here.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :binary_operator_type_mismatch} = e) do
    %{operator: operator, lhs: lhs_type, rhs: rhs_type} = e.details

    """
    Type Mismatch Error: Binary Operator Type Error
      Operator: #{render_operator(operator)}
      Left operand type: #{render_type(lhs_type)}
      Right operand type: #{render_type(rhs_type)}
      --
      The operand types are not compatible with this binary operator.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :string_segment_type_mismatch} = e) do
    %{segment: segment, expected: expected, got: got} = e.details

    """
    Type Mismatch Error: String #{render_string_segment(segment)}
      Expected: #{render_string_segment_expected(expected)}
      Got: #{render_type(got)}
      --
      #{render_string_segment_hint(segment)}
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :logical_operator_type_mismatch} = e) do
    %{operator: operator, lhs: lhs_type, rhs: rhs_type} = e.details

    """
    Type Mismatch Error: Logical Operator Type Error
      Operator: #{render_operator(operator)}
      Left operand type: #{render_type(lhs_type)}
      Right operand type: #{render_type(rhs_type)}
      Expected operand types: :boolean and :boolean
      --
      Logical operators require both operands to be boolean.
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
    Type Mismatch Error: Incompatible Case Branches
    #{lines}
      --
      All case branches must return the same type and result in compatible session states.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :builtin_arg_type_mismatch} = e) do
    %{function: function, expected: expected, got: got} = e.details
    expected_str = expected |> List.wrap() |> Enum.map_join(" | ", &render_type/1)

    """
    Type Mismatch Error: Built-in Argument Type
      Function: #{function}
      Expected: #{expected_str}
      Got: #{render_type(got)}
      --
      This built-in does not accept an argument of that type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :map_update_not_record} = e) do
    %{got: got} = e.details

    """
    Type Mismatch Error: Map Update of a Non-Record
      Expected: a map record
      Got: #{render_type(got)}
      --
      `%{m | k: v}` can only update a map record.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :map_update_key_not_found} = e) do
    %{key: key, record: record} = e.details

    """
    Type Mismatch Error: Map Update Key Not Found
      Key: #{render_type(key)}
      Record: #{render_type(record)}
      --
      `%{m | k: v}` can only update keys the record already has.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :field_access_not_record} = e) do
    %{got: got} = e.details

    """
    Type Mismatch Error: Field Access on a Non-Record
      Expected: a map record
      Got: #{render_type(got)}
      --
      `m.k` can only access a field of a map record.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :field_access_key_not_found} = e) do
    %{key: key, record: record} = e.details

    """
    Type Mismatch Error: Field Access Key Not Found
      Key: #{render_type(key)}
      Record: #{render_type(record)}
      --
      `m.k` can only access keys the record has.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :record_duplicate_label} = e) do
    %{label: label} = e.details

    """
    Type Mismatch Error: Duplicate Record Label
      Label: #{inspect(label)}
      --
      Each label can appear only once in a record.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :invalid_record_label} = e) do
    %{label: label} = e.details

    """
    Type Mismatch Error: Invalid Record Label
      Label: #{inspect(label)}
      --
      `true`, `false` and `nil` cannot be record labels: they are the constants of Bool and Nil.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :record_missing_fields} = e) do
    %{labels: labels, record: record} = e.details

    """
    Type Mismatch Error: Missing Record Fields
      Missing: #{Enum.map_join(labels, ", ", &inspect/1)}
      Expected: #{render_type(record)}
      --
      A record must give every field of its type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :record_unexpected_field} = e) do
    %{label: label, record: record} = e.details

    """
    Type Mismatch Error: Unexpected Record Field
      Field: #{inspect(label)}
      Expected: #{render_type(record)}
      --
      A record can only give the fields of its type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :tuple_arity_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Tuple Arity Mismatch
      Expected size: #{expected}
      Got size: #{got}
      --
      A tuple must have as many elements as its type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :dict_key_not_base_type} = e) do
    %{got: got} = e.details

    """
    Type Mismatch Error: Dict Key Not a Base Type
      Got: #{render_type(got)}
      --
      Dict keys must have a base type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :dict_op_not_dict} = e) do
    %{op: op, got: got} = e.details

    """
    Type Mismatch Error: Dict Operation on a Non-Dict
      Function: #{render_dict_op(op)}
      Expected: a dict
      Got: #{render_type(got)}
      --
      #{render_dict_op_hint(got)}
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :dict_arg_type_mismatch} = e) do
    %{op: op, argument: argument, expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Dict #{render_dict_part(argument)} Type
      Function: #{render_dict_op(op)}
      Expected: #{render_type(expected)}
      Got: #{render_type(got)}
      --
      The #{argument} must have the dict's #{argument} type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :not_a_function} = e) do
    %{got: got} = e.details

    """
    Type Mismatch Error: Application of a Non-Function
      Expected: a function
      Got: #{render_type(got)}
      --
      `f.(...)` can only call a function.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :function_arg_type_mismatch} = e) do
    %{position: position, expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Function Argument Type
      Argument: #{position}
      Expected: #{render_type(expected)}
      Got: #{render_type(got)}
      --
      `f.(...)` was called with an argument of the wrong type.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :lambda_not_expected} = e) do
    %{expected: expected} = e.details

    """
    Type Mismatch Error: Unexpected Anonymous Function
      Expected: #{render_type(expected)}
      Got: an anonymous function
      --
      An anonymous function can only be used where a function is expected.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :lambda_arity_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    Type Mismatch Error: Anonymous Function Arity
      Expected parameters: #{expected}
      Got parameters: #{got}
      --
      The anonymous function must take as many parameters as the function type it is checked against.
    """
  end

  defp render(%Error{category: :type_mismatch, kind: :send_message_not_tuple} = e) do
    %{got: message_ast} = e.details

    """
    Type Mismatch Error: Send Message Not Tuple
      Expected: Tagged tuple message {label, payload}
      Got: #{inspect(message_ast)}
      --
      Messages must be 2-tuples with an atom label and payload.
    """
  end

  # --- :type_inference

  defp render(%Error{category: :type_inference, kind: :cannot_infer_type} = e) do
    %{term: term} = e.details

    """
    Type Inference Error: Cannot Infer Type
      Expression: #{render_uninferable(term)}
      --
      #{render_uninferable_hint(term)}
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :conflicting_pattern_bindings} = e) do
    %{conflicting_vars: conflicting_vars} = e.details

    """
    Pattern Matching Error: Conflicting Pattern Bindings
      Conflicting variables: #{Enum.join(conflicting_vars, ", ")}
      --
      The same variable is bound multiple times in this pattern, which is not allowed.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_type_mismatch} = e) do
    %{pattern: pattern, expected: expected, got: got} = e.details

    """
    Pattern Matching Error: Pattern Type Mismatch
      Pattern: #{render_pattern(pattern)}
      Expected type: #{render_type(expected)}
      Got type: #{render_type(got)}
      --
      The pattern does not match the expected type.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :tuple_arity_mismatch} = e) do
    %{pattern_arity: pattern_arity, expected: expected} = e.details

    """
    Pattern Matching Error: Tuple Arity Mismatch
      Pattern: #{pattern_arity}-tuple
      Expected: #{expected}-tuple
      --
      The tuple pattern has #{pattern_arity} elements but expected #{expected} elements.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :complex_map_key} = e) do
    %{key_ast: key_ast} = e.details

    """
    Pattern Matching Error: Complex Map Key
      Key expression: #{inspect(key_ast)}
      --
      Map keys must be literal atoms (in construction, update and patterns),
      so a record's fields are known statically. Variables, calls and other expressions are not allowed.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_map_key_not_found} = e) do
    %{missing_key: missing_key} = e.details

    """
    Pattern Matching Error: Map Key Not Found
      Missing key: #{render_pattern(missing_key)}
      --
      The pattern references a map key that is not present in the expected map type.
    """
  end

  defp render(%Error{category: :pattern_matching, kind: :pattern_map_key_not_atom} = e) do
    %{key_ast: key_ast} = e.details

    """
    Pattern Matching Error: Map Key Not Atom
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
    Function Call Error: Function Does Not Exist
      Called function: #{func_str}
      --
      The function #{func_str} is not defined in this module.
    """
  end

  defp render(%Error{category: :function_call, kind: :handler_called_directly} = e) do
    %{func_id: {name, _arity} = func_id, handler_kind: handler_kind} = e.details

    how =
      case handler_kind do
        :init -> "Register it instead: register(ap_pid, role, &#{name}/2, args)."
        :message -> "Suspend with it instead: suspend(&#{name}/3, state)."
      end

    """
    Function Call Error: Handler Called Directly
      Called function: #{Utils.to_func(func_id)}
      Handler: #{name} (#{handler_kind} handler)
      --
      Handlers are run by the runtime and cannot be called like functions.
      #{how}
    """
  end

  defp render(%Error{category: :function_call, kind: :application_arity_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    Function Call Error: Wrong Number of Arguments
      Expected arguments: #{expected}
      Got arguments: #{got}
      --
      `f.(...)` must be called with as many arguments as the function takes.
    """
  end

  defp render(%Error{category: :function_call, kind: :function_altered_session_state} = e) do
    %{final_state: final_state} = e.details

    """
    Function Call Error: Function Altered Session State
      Final state: #{inspect(final_state)}
      --
      Function altered the session state when it should remain unchanged.
    """
  end

  defp render(%Error{category: :function_call, kind: :wrong_number_of_clauses} = e) do
    %{expected: expected, got: got} = e.details

    """
    Function Call Error: Wrong Number of Clauses
      Expected clauses: #{expected}
      Got clauses: #{got}
      --
      Incompatible number of clauses defined for function.
    """
  end

  defp render(%Error{category: :function_call, kind: :wrong_number_of_specs} = e) do
    %{expected: expected, got: got} = e.details

    """
    Function Call Error: Wrong Number of Specs
      Expected specs: #{expected |> List.wrap() |> Enum.uniq() |> Enum.join(" or ")}
      Got specs: #{got}
      --
      Incompatible number of @spec annotations defined for function.
    """
  end

  # --- :type_specification

  defp render(%Error{category: :type_specification, kind: :function_spec_info_mismatch} = e) do
    %{spec_id: spec_id, func_id: func_id} = e.details
    spec_str = Utils.to_func(spec_id)
    func_str = Utils.to_func(func_id)

    """
    Type Specification Error: Function Spec Mismatch
      @spec signature: #{spec_str}
      Function signature: #{func_str}
      --
      The @spec annotation does not match the function definition.
    """
  end

  defp render(%Error{category: :type_specification, kind: :spec_args_parse_error_at} = e) do
    %{failed_index: failed_index, args_asts: args_asts, cause: cause} =
      e.details

    {title, opts, message} = render_cause(cause)

    """
    Type Specification Error: Invalid Spec Argument
      Argument types: #{render_type_list(args_asts)}
      Error at argument: ##{failed_index + 1}
      Parse error: #{title}
      #{opts}
      --
      Failed to parse type specification for function argument.

      Details: #{message}
    """
  end

  defp render(%Error{category: :type_specification, kind: :spec_return_not_well_typed} = e) do
    %{return_ast: return_ast, cause: cause} = e.details
    {title, opts, message} = render_cause(cause)

    """
    Type Specification Error: Invalid Spec Return Type
      Return type: #{inspect(return_ast)}
      Parse error: #{title}
      #{opts}
      --
      The return type specification is invalid.

      Details: #{message}
    """
  end

  defp render(%Error{category: :type_specification, kind: :state_type_not_well_typed} = e) do
    %{state: state, type_ast: type_ast, cause: cause} = e.details
    {title, opts, message} = render_cause(cause)

    """
    Type Specification Error: Invalid State Type
      Declaration: #{render_state_declaration(state)}
      Type: #{Macro.to_string(type_ast)}
      Parse error: #{title}
      #{opts}
      --
      The state type is invalid.

      Details: #{message}
    """
  end

  defp render(%Error{category: :type_specification, kind: :module_type_not_well_typed} = e) do
    %{name: name, cause: cause} = e.details
    {title, opts, message} = render_cause(cause)

    """
    Type Specification Error: Invalid Module Type
      Module type: #{name}
      Reason: #{title}
      #{opts}
      --
      The module type is invalid.

      Details: #{message}
    """
  end

  defp render(%Error{category: :type_specification, kind: :no_spec_for_function}) do
    """
    Type Specification Error: Missing Function Spec
      No @spec annotation found for this function. All functions require type specifications.
    """
  end

  # --- :name_resolution

  defp render(%Error{category: :name_resolution, kind: :variable_not_exist} = e) do
    %{var: var} = e.details

    """
    Name Resolution Error: Unbound Variable
      Variable: #{var}
      --
      This variable is not bound in the current scope.
    """
  end

  # --- :framework_usage

  defp render(%Error{category: :framework_usage, kind: :missing_session_registration}) do
    """
    Framework Usage Violation: Missing Session Registration
      Actor does not register in a session in the on_link/2 callback
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unknown_roles} = e) do
    %{protocol: protocol, got: got, known: known} = e.details

    """
    Framework Usage Violation: Unknown Roles
      Got: #{Enum.map_join(got, ", ", &inspect/1)}
      Roles of #{inspect(protocol)}: #{Enum.map_join(known, ", ", &inspect/1)}
      --
      session_type must be given a role of the actor's protocol.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :role_not_literal} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Role Not a Literal
      Got: #{Macro.to_string(got)}
      --
      register must be given the role as a literal atom.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_handler_guard} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Unsupported Handler Guard
      Guard: #{Macro.to_string(got)}
      --
      defhandler does not support guards, annotate the payload with its type instead, as {:label, var :: type()}.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :invalid_handler_head} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Invalid Handler Head
      Got: #{Macro.to_string(got)}
      --
      defhandler must be given name(args, state) for an init handler, or name(role, message, state) for a message handler.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :handler_role_not_literal} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Handler Role Not a Literal
      Got: #{Macro.to_string(got)}
      --
      A message handler must be given the role it receives from as a literal atom.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :handler_name_clash} = e) do
    %{function: {name, arity}, handler_kind: handler_kind} = e.details

    """
    Framework Usage Violation: Function Has a Handler's Name
      Function: #{name}/#{arity}
      Handler: #{name} (#{handler_kind} handler)
      --
      A function cannot have the same name as a handler in the same module, at any arity. Rename one of them.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :init_handler_arg_type_mismatch} = e) do
    %{handler: handler, expected: expected, got: got} = e.details

    """
    Framework Usage Violation: Init Handler Clauses Take Different Types
      Handler: #{handler}
      First clause takes: #{render_type(expected)}
      This clause takes: #{render_type(got)}
      --
      An init handler has one type, so every clause must take the same argument type. Use a separate handler for a different argument type.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :handler_ref_wrong_arity} = e) do
    %{name: name, got: got, expected: expected} = e.details
    kind = handler_ref_kind(expected)

    """
    Framework Usage Violation: Wrong Handler Arity
      Got: &#{name}/#{got}
      Expected: &#{name}/#{expected}
      --
      #{name} is #{kind}, which is referenced with arity #{expected}.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :handler_message_not_tagged_tuple} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Message Not a Tagged Tuple
      Got: #{Macro.to_string(got)}
      --
      A message handler must match a message of the form {:label, payload}.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :missing_global_state}) do
    """
    Framework Usage Violation: Missing Global State
      --
      Maty.Actor must declare its global state type with global_state.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :missing_local_states} = e) do
    %{roles: roles} = e.details

    """
    Framework Usage Violation: Missing Local State
      Roles: #{Enum.map_join(roles, ", ", &inspect/1)}
      --
      Maty.Actor must declare a local state type with local_state for every role it plays.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :duplicate_state_declaration} = e) do
    %{state: state} = e.details

    """
    Framework Usage Violation: Duplicate State Declaration
      Declaration: #{render_state_declaration(state)}
      --
      Maty.Actor must declare its global state once, and the local state of each role once.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :local_state_undeclared_role} = e) do
    %{got: got, known: known} = e.details

    """
    Framework Usage Violation: Undeclared Role
      Got: #{inspect(got)}
      Declared roles: #{Enum.map_join(known, ", ", &inspect/1)}
      --
      local_state must be given a role with a session_type declaration.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :invalid_session_type_declaration} = e) do
    %{reason: reason, got: got} = e.details

    """
    Framework Usage Violation: Invalid Session Type Declaration
      Got: #{Macro.to_string(got)}
      --
      #{render_session_type_declaration(reason)}
    """
  end

  defp render(%Error{category: :framework_usage, kind: :duplicate_handler_session_type} = e) do
    %{handler: handler} = e.details

    """
    Framework Usage Violation: Duplicate Handler Session Type
      Handler: #{handler}
      --
      A handler's session type must be given once, under a single role.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :duplicate_role_session_type} = e) do
    %{role: role} = e.details

    """
    Framework Usage Violation: Duplicate Session Type Declaration
      Role: #{render_atom(role)}
      --
      All of a role's handlers must be given in a single session_type declaration.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :init_handler_role_mismatch} = e) do
    %{expected: expected, got: got} = e.details

    """
    Framework Usage Violation: Init Handler Role Mismatch
      Expected: #{render_atom(expected)}
      Got: #{render_atom(got)}
      --
      MatyDSL.register/4 must be given the role whose session_type declares its init handler.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_anonymous_function}) do
    """
    Framework Usage Violation: Unsupported Anonymous Function
      Anonymous functions are not supported in Maty actors
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_lambda} = e) do
    %{reason: reason} = e.details

    """
    Framework Usage Violation: Unsupported Anonymous Function
      #{render_unsupported_lambda(reason)}
      --
      Only single-clause anonymous functions without guards are supported. Consider a named function.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :communication_in_lambda} = e) do
    %{got: got} = e.details

    """
    Framework Usage Violation: Communication in an Anonymous Function
      Got: #{render_action(got)}
      --
      Anonymous functions cannot communicate. Communicate from the handler or a named function instead.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_bitstring}) do
    """
    Framework Usage Violation: Unsupported Bitstring
      Only string concatenation (<>) and interpolation are supported, not other bitstring syntax
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_expression} = e) do
    %{ast: ast} = e.details

    """
    Framework Usage Violation: Unsupported Expression
      Expression: #{Macro.to_string(ast)}
      --
      Maty does not typecheck this kind of expression.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_pattern} = e) do
    %{ast: ast} = e.details

    """
    Framework Usage Violation: Unsupported Pattern
      Pattern: #{Macro.to_string(ast)}
      --
      Maty does not typecheck this kind of pattern (guards are not supported).
    """
  end

  defp render(%Error{category: :framework_usage, kind: :unsupported_truthy_operator} = e) do
    %{op: op} = e.details

    """
    Framework Usage Violation: Unsupported Operator
      Operator: #{op}
      --
      `&&` and `||` treat nil and false as false and return one of their operands.
      Use `and` / `or`, which take and return booleans.
    """
  end

  defp render(%Error{category: :framework_usage, kind: :no_native_send}) do
    """
    Framework Usage Violation: Attempted Native Communication
      Actor attempted communication using send/2
    """
  end

  defp render(%Error{category: :framework_usage, kind: :no_native_receive}) do
    """
    Framework Usage Violation: Attempted Native Communication
      Actor attempted communication using a receive block
    """
  end

  # --- :internal (one generic clause for all internal diagnostics)

  defp render(%Error{category: :internal} = e) do
    """
    Internal Error
      #{e.details[:message]}
    """
  end

  # todo: add `@spec`
  defp render_action({action, args}),
    do: "MatyDSL.#{action}(#{Enum.map_join(args, ", ", &Macro.to_string/1)})"

  # an Error.Cause as {title, details line(s), explanation}, for the parent error's render clause
  defp render_cause(%Error.Cause{kind: :unsupported_type_constructor, details: %{type_ast: ast}}) do
    {"Unsupported Type Constructor", "Type AST: #{inspect(ast)}",
     "This type specification AST structure is not supported by the typechecker."}
  end

  defp render_cause(%Error.Cause{kind: :invalid_record_label, details: %{label: label}}) do
    {"Invalid Record Label", "Label: #{inspect(label)}",
     "`true`, `false` and `nil` cannot be record labels: they are the constants of Bool and Nil."}
  end

  defp render_cause(%Error.Cause{kind: :unknown_type_constructor, details: %{type: type}}) do
    {"Unknown Type Constructor", "Type: #{type}",
     "Unknown type constructor or type atom not found in the type environment."}
  end

  defp render_cause(%Error.Cause{kind: :empty_record}) do
    {"Empty Record Type", "Type: %{}",
     "A record type needs at least one field. Use nil for a value that carries nothing."}
  end

  defp render_cause(%Error.Cause{kind: :dict_key_not_base_type, details: %{key_type: key_type}}) do
    {"Dict Key Not a Base Type", "Key type: #{render_type(key_type)}",
     "Dict keys must have a base type."}
  end

  defp render_cause(%Error.Cause{kind: :recursive_type, details: %{through: through}}) do
    {"Recursive Type", "Through: #{through}()",
     "A type cannot use itself, directly or through other module types."}
  end

  defp render_cause(%Error.Cause{kind: :parametric_type, details: %{name: name, arity: arity}}) do
    {"Parametric Type", "Type: #{name}/#{arity}", "Types with parameters are not supported."}
  end

  defp render_cause(%Error.Cause{kind: :remote_type, details: %{type_ast: type_ast}}) do
    {"Remote Type", "Type: #{Macro.to_string(type_ast)}",
     "Types defined in other modules are not supported."}
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

  defp render_frame({:argument, index}), do: "in argument ##{index}"

  defp render_frame({:message_payload, label, st}),
    do: "in the payload of message `#{render_atom(label)}`, sent at `#{Maty.ST.repr(st)}`"

  defp render_frame({:state, action}), do: "in the state given to #{action}"
  defp render_frame(:init_handler_args), do: "in the init handler's argument"
  defp render_frame(:access_point), do: "in the access point"
  defp render_frame({:tuple_element, index}), do: "in tuple element ##{index}"
  defp render_frame({:list_element, index}), do: "in list element ##{index}"
  defp render_frame(:list_tail), do: "in the list tail"
  defp render_frame({:dict_key, index}), do: "in the key of dict entry ##{index}"
  defp render_frame({:dict_value, index}), do: "in the value of dict entry ##{index}"
  defp render_frame({:record_field, label}), do: "in record field #{inspect(label)}"

  defp render_line(meta) do
    case Keyword.get(meta, :line) do
      nil -> ""
      line -> " (line #{line})"
    end
  end

  defp render_atom(elt) when is_atom(elt), do: ":#{elt}"
  defp render_atom(elt), do: "#{inspect(elt)}"

  defp render_pattern(pattern), do: Macro.to_string(pattern)

  defp render_type(nil), do: "nil"
  defp render_type(type) when is_atom(type), do: ":#{type}"

  # todo: make the representations not suck
  defp render_type({:handler, :message, role, st}),
    do: "message handler of #{render_atom(role)} for #{Maty.ST.repr(st)}"

  # an init handler has one argument type, the same for all of its clauses
  defp render_type({:handler, :init, role, arg_type, st}),
    do:
      "init handler of #{render_atom(role)} taking #{render_type(arg_type)} for #{Maty.ST.repr(st)}"

  defp render_type(type), do: "#{inspect(type)}"

  # an expected type, or a description where there is no single type to show
  defp render_expected(description) when is_binary(description), do: description
  defp render_expected(type), do: render_type(type)

  defp render_state_declaration(:global), do: "global_state"
  defp render_state_declaration({:local, role}), do: "local_state #{inspect(role)}"

  defp render_session_type_declaration(:role_not_literal),
    do: "session_type must be given the role as a literal atom."

  defp render_session_type_declaration(:handlers_not_map),
    do: "session_type must be given a map literal from handler names to session types."

  defp render_session_type_declaration(:handler_name_not_literal),
    do: "Each handler name in a session_type must be a literal atom."

  defp render_session_type_declaration(:not_a_session_type),
    do: "Each handler in a session_type must be given a session type"

  defp render_handler_ref(name, arity) when is_atom(name), do: "&#{name}/#{arity}"

  defp handler_ref_kind(2), do: "an init handler"
  defp handler_ref_kind(3), do: "a message handler"

  defp render_string_segment(:interpolation), do: "Interpolation"
  defp render_string_segment(:concatenation), do: "Concatenation"

  defp render_string_segment_expected([type]), do: render_type(type)

  defp render_string_segment_expected(types),
    do: "one of: " <> Enum.map_join(types, ", ", &render_type/1)

  defp render_string_segment_hint(:interpolation),
    do: "This value cannot be converted to a string."

  defp render_string_segment_hint(:concatenation),
    do: "Both operands of <> must be binaries."

  defp render_dict_op(:put), do: "Map.put/3"
  defp render_dict_op(:fetch!), do: "Map.fetch!/2"
  defp render_dict_op(:delete), do: "Map.delete/2"

  defp render_dict_op_hint({:map_record, _}),
    do:
      "This is a record, not a dict: update it with %{m | k: v}, read it with m.k. Record fields cannot be deleted."

  defp render_dict_op_hint(_got),
    do: "Map.put/3, Map.fetch!/2 and Map.delete/2 only work on dicts."

  defp render_dict_part(:key), do: "Key"
  defp render_dict_part(:value), do: "Value"

  defp render_uninferable(:empty_list), do: "[]"
  defp render_uninferable(:empty_map), do: "%{}"
  defp render_uninferable(:anonymous_function), do: "an anonymous function"

  defp render_uninferable_hint(:anonymous_function),
    do:
      "The types of its parameters cannot be inferred here. Use it where a function type is expected, or consider creating a named function."

  defp render_uninferable_hint(:empty_list),
    do: "The type of its elements cannot be inferred here."

  defp render_uninferable_hint(:empty_map),
    do: "The types of its keys and values cannot be inferred here."

  defp render_unsupported_lambda(:multiple_clauses),
    do: "The anonymous function has more than one clause."

  defp render_unsupported_lambda(:guard), do: "The anonymous function has a guard."

  defp render_operator(op) when is_atom(op), do: "#{op}"
  defp render_operator(op), do: "#{inspect(op)}"

  defp render_type_list(types) when is_list(types) do
    Enum.map(types, &inspect/1) |> Enum.join(", ")
  end

  defp render_type_list(type), do: inspect(type)
end
