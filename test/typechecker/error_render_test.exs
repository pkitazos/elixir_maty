defmodule Maty.Typechecker.ErrorRenderTest do
  use ExUnit.Case

  alias Maty.Typechecker.Error
  alias Maty.Typechecker.Error.Formatter

  # One error built by every constructor, rendered by the Formatter to catch a constructor without a render clause

  @m TwoBuyer.Seller
  @meta [line: 7, column: 3]
  @st_end %ST.SEnd{}
  @branch %ST.SBranch{label: :title, payload: :binary, continue_as: @st_end}
  @st_in %ST.SIn{from: :buyer1, branches: [@branch]}
  @st_out %ST.SOut{to: :seller, branches: [@branch]}
  @cause Error.TypeSpecification.unknown_type_constructor(:wat)

  # the modules whose public functions are error constructors

  @constructor_modules [
    Error.ProtocolViolation,
    Error.TypeMismatch,
    Error.PatternMatching,
    Error.FunctionCall,
    Error.TypeSpecification,
    Error.FrameworkUsage,
    Error.NameResolution,
    Error.TypeInference
  ]

  @cause_constructors [
    {Error.TypeMismatch, :invalid_maty_state_cause},
    {Error.TypeSpecification, :unsupported_type_constructor},
    {Error.TypeSpecification, :invalid_record_label},
    {Error.TypeSpecification, :unknown_type_constructor},
    {Error.TypeSpecification, :empty_record},
    {Error.TypeSpecification, :dict_key_not_base_type},
    {Error.TypeSpecification, :recursive_type},
    {Error.TypeSpecification, :parametric_type},
    {Error.TypeSpecification, :remote_type}
  ]

  defp errors do
    [
      # :protocol_violation
      {{Error.ProtocolViolation, :missing_handler},
       Error.ProtocolViolation.missing_handler(@m, :title_handler, @meta)},
      {{Error.ProtocolViolation, :init_handler_starts_with_receive},
       Error.ProtocolViolation.init_handler_starts_with_receive(@m, @meta, :install, @st_in)},
      {{Error.ProtocolViolation, :message_handler_not_receive},
       Error.ProtocolViolation.message_handler_not_receive(@m, @meta, :title_handler, @st_out)},
      {{Error.ProtocolViolation, :incorrect_action},
       Error.ProtocolViolation.incorrect_action(
         @m,
         @meta,
         [got: {:send, [:seller, {:title, "a title"}]}],
         @st_in
       )},
      {{Error.ProtocolViolation, :incorrect_recipient_participant},
       Error.ProtocolViolation.incorrect_recipient_participant(@m, @meta, :title_handler, @st_in,
         received: :buyer2,
         expected: :buyer1
       )},
      {{Error.ProtocolViolation, :incorrect_incoming_message_label},
       Error.ProtocolViolation.incorrect_incoming_message_label(
         @m,
         @meta,
         :title_handler,
         @st_in,
         got: :name,
         expected: [:title]
       )},
      {{Error.ProtocolViolation, :incorrect_target_participant},
       Error.ProtocolViolation.incorrect_target_participant(@m, @meta, @st_out,
         got: :buyer2,
         expected: :seller
       )},
      {{Error.ProtocolViolation, :incorrect_message_label},
       Error.ProtocolViolation.incorrect_message_label(@m, @meta, @st_out,
         got: :name,
         expected: [:title]
       )},
      {{Error.ProtocolViolation, :incorrect_payload_type},
       Error.ProtocolViolation.incorrect_payload_type(@m, @meta, @st_out,
         got: :number,
         expected: :binary
       )},
      {{Error.ProtocolViolation, :incorrect_choice_implementation},
       Error.ProtocolViolation.incorrect_choice_implementation(
         @m,
         @meta,
         :title_handler,
         @st_in.branches,
         @st_in
       )},
      {{Error.ProtocolViolation, :undefined_continuation_handler},
       Error.ProtocolViolation.undefined_continuation_handler(
         @m,
         @meta,
         %ST.SName{handler: :decision_handler},
         :decision_handler
       )},
      {{Error.ProtocolViolation, :handler_session_type_mismatch},
       Error.ProtocolViolation.handler_session_type_mismatch(
         @m,
         @meta,
         %ST.SName{handler: :decision_handler},
         :decision_handler,
         got: @st_in,
         expected: %ST.SIn{from: :buyer2, branches: [@branch]}
       )},
      {{Error.ProtocolViolation, :handler_role_mismatch},
       Error.ProtocolViolation.handler_role_mismatch(
         @m,
         @meta,
         %ST.SName{handler: :decision_handler},
         :decision_handler,
         expected: :buyer2,
         got: :buyer1
       )},
      {{Error.ProtocolViolation, :handler_body_wrong_termination},
       Error.ProtocolViolation.handler_body_wrong_termination(
         @meta,
         :title_handler,
         :number,
         @st_out
       )},

      # :type_mismatch
      {{Error.TypeMismatch, :arithmetic_operator_requires_number},
       Error.TypeMismatch.arithmetic_operator_requires_number(@m, @meta, :-, :binary)},
      {{Error.TypeMismatch, :logical_operator_requires_boolean},
       Error.TypeMismatch.logical_operator_requires_boolean(@m, @meta, :not, :number)},
      {{Error.TypeMismatch, :handler_expected},
       Error.TypeMismatch.handler_expected(
         @m,
         @meta,
         :message,
         {:handler, :init, :seller, :binary, @st_out}
       )},
      {{Error.TypeMismatch, :return_type_mismatch},
       Error.TypeMismatch.return_type_mismatch(@m, @meta, expected: :number, got: :binary)},
      {{Error.TypeMismatch, :binary_operator_type_mismatch},
       Error.TypeMismatch.binary_operator_type_mismatch(@m, @meta, :+, :number, :binary)},
      {{Error.TypeMismatch, :logical_operator_type_mismatch},
       Error.TypeMismatch.logical_operator_type_mismatch(@m, @meta, :and, :boolean, :number)},
      {{Error.TypeMismatch, :case_branches_incompatible},
       Error.TypeMismatch.case_branches_incompatible(@m, @meta,
         t1: :number,
         t2: :binary,
         q1: @st_end,
         q2: @st_out
       )},
      {{Error.TypeMismatch, :invalid_maty_state_type},
       Error.TypeMismatch.invalid_maty_state_type(
         @m,
         @meta,
         Error.TypeMismatch.invalid_maty_state_cause(
           expected: {:map_record, %{global: :number, local: :binary}},
           got: :number
         )
       )},
      {{Error.TypeMismatch, :send_message_not_tuple},
       Error.TypeMismatch.send_message_not_tuple(@m, @meta, got: {:title, [], nil})},
      {{Error.TypeMismatch, :register_arg_type_mismatch},
       Error.TypeMismatch.register_arg_type_mismatch(@m, @meta, :init_handler_args,
         expected: :binary,
         got: :number
       )},
      {{Error.TypeMismatch, :string_segment_type_mismatch},
       Error.TypeMismatch.string_segment_type_mismatch(@m, @meta, :interpolation,
         expected: [:atom, :binary],
         got: :pid
       )},
      {{Error.TypeMismatch, :builtin_arg_type_mismatch},
       Error.TypeMismatch.builtin_arg_type_mismatch(@m, @meta, "IO.puts",
         expected: [:binary],
         got: :number
       )},
      {{Error.TypeMismatch, :map_update_not_record},
       Error.TypeMismatch.map_update_not_record(@m, @meta, got: :number)},
      {{Error.TypeMismatch, :map_update_key_not_found},
       Error.TypeMismatch.map_update_key_not_found(
         @m,
         @meta,
         :missing,
         {:map_record, %{name: :binary}}
       )},
      {{Error.TypeMismatch, :invalid_record_label},
       Error.TypeMismatch.invalid_record_label(@m, @meta, true)},
      {{Error.TypeMismatch, :record_duplicate_label},
       Error.TypeMismatch.record_duplicate_label(@m, @meta, :name)},
      {{Error.TypeMismatch, :record_missing_fields},
       Error.TypeMismatch.record_missing_fields(
         @m,
         @meta,
         [:age],
         {:map_record, %{name: :binary, age: :number}}
       )},
      {{Error.TypeMismatch, :record_unexpected_field},
       Error.TypeMismatch.record_unexpected_field(
         @m,
         @meta,
         :email,
         {:map_record, %{name: :binary}}
       )},
      {{Error.TypeMismatch, :tuple_arity_mismatch},
       Error.TypeMismatch.tuple_arity_mismatch(@m, @meta, expected: 2, got: 3)},
      {{Error.TypeMismatch, :expected},
       Error.TypeMismatch.expected(@m, @meta, expected: :number, got: :binary)},
      {{Error.TypeMismatch, :field_access_not_record},
       Error.TypeMismatch.field_access_not_record(@m, @meta, got: :number)},
      {{Error.TypeMismatch, :field_access_key_not_found},
       Error.TypeMismatch.field_access_key_not_found(
         @m,
         @meta,
         :missing,
         {:map_record, %{name: :binary}}
       )},
      {{Error.TypeMismatch, :dict_op_not_dict},
       Error.TypeMismatch.dict_op_not_dict(@m, @meta, :put, got: {:map_record, %{name: :binary}})},
      {{Error.TypeMismatch, :dict_arg_type_mismatch},
       Error.TypeMismatch.dict_arg_type_mismatch(@m, @meta, :fetch!, :key,
         expected: :binary,
         got: :number
       )},
      {{Error.TypeMismatch, :dict_key_not_base_type},
       Error.TypeMismatch.dict_key_not_base_type(@m, @meta, got: {:list, :number})},
      {{Error.TypeMismatch, :not_a_function},
       Error.TypeMismatch.not_a_function(@m, @meta, got: :number)},
      {{Error.TypeMismatch, :function_arg_type_mismatch},
       Error.TypeMismatch.function_arg_type_mismatch(@m, @meta, 1,
         expected: :number,
         got: :binary
       )},
      {{Error.TypeMismatch, :lambda_not_expected},
       Error.TypeMismatch.lambda_not_expected(@m, @meta, expected: :number)},
      {{Error.TypeMismatch, :lambda_arity_mismatch},
       Error.TypeMismatch.lambda_arity_mismatch(@m, @meta, expected: 1, got: 2)},

      # :type_inference
      {{Error.TypeInference, :cannot_infer_type},
       Error.TypeInference.cannot_infer_type(@m, @meta, :anonymous_function)},

      # :pattern_matching
      {{Error.PatternMatching, :conflicting_pattern_bindings},
       Error.PatternMatching.conflicting_pattern_bindings(@m, @meta, [:x, :y])},
      {{Error.PatternMatching, :pattern_type_mismatch},
       Error.PatternMatching.pattern_type_mismatch(@m, @meta,
         pattern: 1,
         expected: :binary,
         got: :number
       )},
      {{Error.PatternMatching, :tuple_arity_mismatch},
       Error.PatternMatching.tuple_arity_mismatch(@m, @meta, pattern_arity: 2, expected: 3)},
      {{Error.PatternMatching, :complex_map_key},
       Error.PatternMatching.complex_map_key(@m, @meta, {:foo, [], [1]})},
      {{Error.PatternMatching, :pattern_map_key_not_found},
       Error.PatternMatching.pattern_map_key_not_found(@m, @meta, :name)},
      {{Error.PatternMatching, :pattern_map_key_not_atom},
       Error.PatternMatching.pattern_map_key_not_atom(@m, @meta, "name")},

      # :function_call
      {{Error.FunctionCall, :function_not_exist},
       Error.FunctionCall.function_not_exist(@m, @meta, {:f, 1})},
      {{Error.FunctionCall, :handler_called_directly},
       Error.FunctionCall.handler_called_directly(@m, @meta, {:install, 3}, :init)},
      {{Error.FunctionCall, :application_arity_mismatch},
       Error.FunctionCall.application_arity_mismatch(@m, @meta, expected: 1, got: 2)},
      {{Error.FunctionCall, :no_matching_function_clause},
       Error.FunctionCall.no_matching_function_clause(@m, @meta, {:f, 1}, [:binary])},
      {{Error.FunctionCall, :function_altered_session_state},
       Error.FunctionCall.function_altered_session_state(@m, @meta, {:f, 1}, @st_out)},
      {{Error.FunctionCall, :wrong_number_of_clauses},
       Error.FunctionCall.wrong_number_of_clauses(@m, @meta, {:on_start, 1}, expected: 1, got: 2)},
      {{Error.FunctionCall, :wrong_number_of_specs},
       Error.FunctionCall.wrong_number_of_specs(@m, @meta, {:f, 1}, expected: 1, got: 2)},

      # :type_specification
      {{Error.TypeSpecification, :spec_return_not_well_typed},
       Error.TypeSpecification.spec_return_not_well_typed(
         @m,
         @meta,
         :f,
         {:wat, [], []},
         @cause
       )},
      {{Error.TypeSpecification, :state_type_not_well_typed},
       Error.TypeSpecification.state_type_not_well_typed(
         @m,
         @meta,
         {:local, :seller},
         {:wat, [], []},
         @cause
       )},
      {{Error.TypeSpecification, :module_type_not_well_typed},
       Error.TypeSpecification.module_type_not_well_typed(@m, @meta, :order, @cause)},
      {{Error.TypeSpecification, :spec_args_parse_error_at},
       Error.TypeSpecification.spec_args_parse_error_at(
         @m,
         @meta,
         {:f, 1},
         0,
         [{:wat, [], []}],
         @cause
       )},
      {{Error.TypeSpecification, :function_spec_info_mismatch},
       Error.TypeSpecification.function_spec_info_mismatch(@m, @meta,
         spec_id: {:g, 1},
         func_id: {:f, 1}
       )},
      {{Error.TypeSpecification, :no_spec_for_function},
       Error.TypeSpecification.no_spec_for_function(@m, @meta, {:f, 1})},

      # :framework_usage
      {{Error.FrameworkUsage, :no_native_send}, Error.FrameworkUsage.no_native_send(@m, @meta)},
      {{Error.FrameworkUsage, :no_native_receive},
       Error.FrameworkUsage.no_native_receive(@m, @meta)},
      {{Error.FrameworkUsage, :unsupported_anonymous_function},
       Error.FrameworkUsage.unsupported_anonymous_function(@m, @meta)},
      {{Error.FrameworkUsage, :unsupported_lambda},
       Error.FrameworkUsage.unsupported_lambda(@m, @meta, :multiple_clauses)},
      {{Error.FrameworkUsage, :communication_in_lambda},
       Error.FrameworkUsage.communication_in_lambda(@m, @meta,
         got: {:send, [:seller, {:title, "a title"}]}
       )},
      {{Error.FrameworkUsage, :unsupported_bitstring},
       Error.FrameworkUsage.unsupported_bitstring(@m, @meta)},
      {{Error.FrameworkUsage, :unsupported_expression},
       Error.FrameworkUsage.unsupported_expression(
         @m,
         @meta,
         {{:., [], [String, :length]}, [], ["a"]}
       )},
      {{Error.FrameworkUsage, :unsupported_truthy_operator},
       Error.FrameworkUsage.unsupported_truthy_operator(@m, @meta, :&&)},
      {{Error.FrameworkUsage, :unsupported_pattern},
       Error.FrameworkUsage.unsupported_pattern(@m, @meta, {:when, [], [{:n, [], nil}, true]})},
      {{Error.FrameworkUsage, :missing_session_registration},
       Error.FrameworkUsage.missing_session_registration(@m, @meta)},
      {{Error.FrameworkUsage, :unknown_roles},
       Error.FrameworkUsage.unknown_roles(@m, @meta, TwoBuyer.Protocol, [:sellr], [
         :buyer1,
         :buyer2,
         :seller
       ])},
      {{Error.FrameworkUsage, :role_not_literal},
       Error.FrameworkUsage.role_not_literal(@m, @meta, {:role, [], nil})},
      {{Error.FrameworkUsage, :init_handler_role_mismatch},
       Error.FrameworkUsage.init_handler_role_mismatch(@m, @meta,
         expected: :seller,
         got: :buyer1
       )},
      {{Error.FrameworkUsage, :missing_global_state},
       Error.FrameworkUsage.missing_global_state(@m, @meta)},
      {{Error.FrameworkUsage, :missing_local_states},
       Error.FrameworkUsage.missing_local_states(@m, @meta, [:seller])},
      {{Error.FrameworkUsage, :duplicate_state_declaration},
       Error.FrameworkUsage.duplicate_state_declaration(@m, @meta, :global)},
      {{Error.FrameworkUsage, :local_state_undeclared_role},
       Error.FrameworkUsage.local_state_undeclared_role(@m, @meta, :buyer1, [:seller])},
      {{Error.FrameworkUsage, :invalid_session_type_declaration},
       Error.FrameworkUsage.invalid_session_type_declaration(
         @m,
         @meta,
         :handler_name_not_literal,
         "install"
       )},
      {{Error.FrameworkUsage, :duplicate_handler_session_type},
       Error.FrameworkUsage.duplicate_handler_session_type(@m, @meta, :install)},
      {{Error.FrameworkUsage, :duplicate_role_session_type},
       Error.FrameworkUsage.duplicate_role_session_type(@m, @meta, :seller)},
      {{Error.FrameworkUsage, :unsupported_handler_guard},
       Error.FrameworkUsage.unsupported_handler_guard(
         @m,
         @meta,
         {:is_binary, [], [{:t, [], nil}]}
       )},
      {{Error.FrameworkUsage, :invalid_handler_head},
       Error.FrameworkUsage.invalid_handler_head(@m, @meta, {:install, [], [{:state, [], nil}]})},
      {{Error.FrameworkUsage, :handler_role_not_literal},
       Error.FrameworkUsage.handler_role_not_literal(@m, @meta, {:from, [], nil})},
      {{Error.FrameworkUsage, :handler_message_not_tagged_tuple},
       Error.FrameworkUsage.handler_message_not_tagged_tuple(@m, @meta, {:msg, [], nil})},
      {{Error.FrameworkUsage, :handler_name_clash},
       Error.FrameworkUsage.handler_name_clash(@m, @meta, {:install, 3}, :init)},
      {{Error.FrameworkUsage, :init_handler_arg_type_mismatch},
       Error.FrameworkUsage.init_handler_arg_type_mismatch(@m, @meta, :install,
         expected: :number,
         got: :binary
       )},
      {{Error.FrameworkUsage, :handler_ref_wrong_arity},
       Error.FrameworkUsage.handler_ref_wrong_arity(@m, @meta, :install, 3, 2)},

      # :name_resolution
      {{Error.NameResolution, :variable_not_exist},
       Error.NameResolution.variable_not_exist(@m, @meta, :x)},

      # :internal
      {{Error, :internal_error}, Error.internal_error("unexpected result")}
    ]
  end

  test "every error constructor is covered here" do
    constructors =
      for mod <- @constructor_modules,
          {name, _arity} <- mod.__info__(:functions),
          {mod, name} not in @cause_constructors,
          uniq: true,
          do: {mod, name}

    covered = MapSet.new(errors(), fn {constructor, _error} -> constructor end)
    missing = Enum.reject(constructors, &MapSet.member?(covered, &1))

    assert missing == [],
           "add these constructors to errors/0 in this test: #{inspect(missing)}"
  end

  test "every error renders" do
    for {constructor, error} <- errors() do
      assert %Error{} = error

      rendered =
        try do
          Formatter.format(error)
        rescue
          e -> flunk("#{inspect(constructor)} failed to render: #{Exception.message(e)}")
        end

      assert String.trim(rendered) != "", "#{inspect(constructor)} rendered nothing"
    end
  end

  test "trace frames are appended after the error body" do
    error = %{
      Error.ProtocolViolation.incorrect_recipient_participant(@m, @meta, :title_handler, @st_in,
        received: :buyer2,
        expected: :buyer1
      )
      | trace: [
          {:call, {:process_title, 2}, [line: 40]},
          {:clause, {:title_handler, 4}, 1}
        ]
    }

    rendered = Formatter.format(error)

    assert rendered =~ "  Trace:\n"
    assert rendered =~ "    via process_title/2 (line 40)\n"
    assert rendered =~ "    in clause #1 of title_handler/4"
    assert rendered =~ ~r/Session Type: .*\n  Trace:/s
  end
end
