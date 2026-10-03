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
    Error.NameResolution
  ]

  @cause_constructors [
    {Error.TypeMismatch, :invalid_maty_state_cause},
    {Error.TypeSpecification, :unsupported_type_constructor},
    {Error.TypeSpecification, :unknown_type_constructor},
    {Error.TypeSpecification, :heterogeneous_list_error}
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
       Error.ProtocolViolation.incorrect_action(@m, @meta, [got: :send], @st_in)},
      {{Error.ProtocolViolation, :incorrect_recipient_participant},
       Error.ProtocolViolation.incorrect_recipient_participant(@m, @meta, :title_handler, @st_in,
         received: :buyer2,
         declared: :buyer1,
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
      {{Error.ProtocolViolation, :incorrect_incoming_payload_type},
       Error.ProtocolViolation.incorrect_incoming_payload_type(
         @m,
         @meta,
         :title_handler,
         @st_in,
         got: :number,
         expected: :binary
       )},
      {{Error.ProtocolViolation, :incorrect_target_participant},
       Error.ProtocolViolation.incorrect_target_participant(@m, @meta, @st_out,
         got: :buyer2,
         expected: :seller
       )},
      {{Error.ProtocolViolation, :incorrect_handler_suspension},
       Error.ProtocolViolation.incorrect_handler_suspension(@m, @meta, %ST.SName{handler: :h},
         got: :other_handler,
         expected: :h
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
         Maty.ST.repr(@st_in),
         @st_in
       )},
      {{Error.ProtocolViolation, :suspend_invalid_handler_type},
       Error.ProtocolViolation.suspend_invalid_handler_type(@m, @meta, [got: :number], @st_out)},
      {{Error.ProtocolViolation, :case_scrutinee_altered_state},
       Error.ProtocolViolation.case_scrutinee_altered_state(@meta, from: @st_out, to: @st_end)},
      {{Error.ProtocolViolation, :handler_body_wrong_termination},
       Error.ProtocolViolation.handler_body_wrong_termination(
         @meta,
         :title_handler,
         :number,
         @st_out
       )},

      # :type_mismatch
      {{Error.TypeMismatch, :logical_operator_requires_boolean},
       Error.TypeMismatch.logical_operator_requires_boolean(@m, @meta, :not, :number)},
      {{Error.TypeMismatch, :return_type_mismatch},
       Error.TypeMismatch.return_type_mismatch(@m, @meta, expected: :number, got: :binary)},
      {{Error.TypeMismatch, :binary_operator_type_mismatch},
       Error.TypeMismatch.binary_operator_type_mismatch(@m, @meta, :+, :number, :binary)},
      {{Error.TypeMismatch, :logical_operator_type_mismatch},
       Error.TypeMismatch.logical_operator_type_mismatch(@m, @meta, :and, :boolean, :number)},
      {{Error.TypeMismatch, :list_elements_incompatible},
       Error.TypeMismatch.list_elements_incompatible(@m, @meta, [:number, :binary])},
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
         Error.TypeMismatch.invalid_maty_state_cause(:number)
       )},
      {{Error.TypeMismatch, :send_message_not_tuple},
       Error.TypeMismatch.send_message_not_tuple(@m, @meta, got: {:title, [], nil})},
      {{Error.TypeMismatch, :register_arg_type_mismatch},
       Error.TypeMismatch.register_arg_type_mismatch(@m, @meta, :init_handler,
         expected: "a function",
         got: :atom
       )},
      {{Error.TypeMismatch, :builtin_arg_type_mismatch},
       Error.TypeMismatch.builtin_arg_type_mismatch(@m, @meta, "IO.puts",
         expected: [:binary],
         got: :number
       )},

      # :pattern_matching
      {{Error.PatternMatching, :conflicting_pattern_bindings},
       Error.PatternMatching.conflicting_pattern_bindings(@m, @meta, "x, y")},
      {{Error.PatternMatching, :pattern_type_mismatch},
       Error.PatternMatching.pattern_type_mismatch(@m, @meta,
         pattern: 1,
         expected: :binary,
         got: :number
       )},
      {{Error.PatternMatching, :pattern_arity_mismatch},
       Error.PatternMatching.pattern_arity_mismatch(@m, @meta,
         pattern: :tuple,
         expected: 2,
         got: 3
       )},
      {{Error.PatternMatching, :tuple_arity_mismatch},
       Error.PatternMatching.tuple_arity_mismatch(@m, @meta, pattern_arity: 2, expected: 3)},
      {{Error.PatternMatching, :pattern_not_tuple},
       Error.PatternMatching.pattern_not_tuple(@m, @meta, got: :number)},
      {{Error.PatternMatching, :complex_map_key},
       Error.PatternMatching.complex_map_key(@m, @meta, {:foo, [], [1]})},
      {{Error.PatternMatching, :invalid_map_key_type},
       Error.PatternMatching.invalid_map_key_type(@m, @meta, expected: :atom, got: :number)},
      {{Error.PatternMatching, :pattern_map_key_not_found},
       Error.PatternMatching.pattern_map_key_not_found(@m, @meta, :name)},
      {{Error.PatternMatching, :pattern_map_key_not_atom},
       Error.PatternMatching.pattern_map_key_not_atom(@m, @meta, "name")},

      # :function_call
      {{Error.FunctionCall, :function_not_exist},
       Error.FunctionCall.function_not_exist(@m, @meta, {:f, 1})},
      {{Error.FunctionCall, :arity_mismatch},
       Error.FunctionCall.arity_mismatch(@m, @meta, {:f, 1}, expected: 1, got: 2)},
      {{Error.FunctionCall, :no_matching_function_clause},
       Error.FunctionCall.no_matching_function_clause(@m, @meta, {:f, 1}, [:binary])},
      {{Error.FunctionCall, :function_altered_session_state},
       Error.FunctionCall.function_altered_session_state(@m, @meta, {:f, 1}, @st_out)},
      {{Error.FunctionCall, :wrong_number_of_clauses},
       Error.FunctionCall.wrong_number_of_clauses(@m, @meta, {:on_link, 2}, expected: 1, got: 2)},
      {{Error.FunctionCall, :wrong_number_of_specs},
       Error.FunctionCall.wrong_number_of_specs(@m, @meta, {:f, 1}, expected: "1 or 3", got: 2)},

      # :type_specification
      {{Error.TypeSpecification, :invalid_session_type_annotation},
       Error.TypeSpecification.invalid_session_type_annotation(@m, @meta, :title_handler, @cause)},
      {{Error.TypeSpecification, :spec_return_not_well_typed},
       Error.TypeSpecification.spec_return_not_well_typed(
         @m,
         @meta,
         :f,
         {:wat, [], []},
         @cause
       )},
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
      {{Error.FrameworkUsage, :missing_session_registration},
       Error.FrameworkUsage.missing_session_registration(@m, @meta)},
      {{Error.FrameworkUsage, :on_link_altered_session_state},
       Error.FrameworkUsage.on_link_altered_session_state(@m, @meta, @st_out)},
      {{Error.FrameworkUsage, :on_link_bad_return},
       Error.FrameworkUsage.on_link_bad_return(@m, @meta, :number)},
      {{Error.FrameworkUsage, :invalid_init_handler},
       Error.FrameworkUsage.invalid_init_handler(@m, @meta)},

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

    assert Enum.reject(constructors, &MapSet.member?(covered, &1)) == [],
           "add the constructors above to errors/0 in this test"
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

      assert rendered =~ "** (ElixirMatyTypeError)",
             "#{inspect(constructor)} rendered without the error header"
    end
  end
end
