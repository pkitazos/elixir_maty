defmodule Maty.Typechecker.HelpersTest do
  use ExUnit.Case

  alias Maty.Typechecker.{Helpers, Ctx}
  alias Maty.ST.SBottom
  alias Maty.Types.T, as: Type

  @meta [line: 0]
  @module TestModule
  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)
  @ctx %Ctx{module: @module, meta: @meta}

  # --- unify_list_types/1 ---

  describe "unify_list_types/1" do
    test "empty list returns :any" do
      assert {:ok, :any} = Helpers.unify_list_types([])
    end

    test "homogeneous list returns element type" do
      assert {:ok, :number} = Helpers.unify_list_types([:number, :number, :number])
    end

    test "single element list returns that type" do
      assert {:ok, :binary} = Helpers.unify_list_types([:binary])
    end

    test "heterogeneous list returns error" do
      assert {:error, :incompatible} = Helpers.unify_list_types([:number, :binary])
    end

    test "non-list input returns error" do
      assert {:error, :incompatible} = Helpers.unify_list_types(:number)
    end
  end

  # --- is_base_type?/1 ---

  describe "is_base_type?/1" do
    test "all base types return true" do
      for type <- [:atom, nil, :boolean, :number, :binary, :date, :pid, :ref] do
        assert Helpers.is_base_type?(type), "expected #{inspect(type)} to be a base type"
      end
    end

    test "compound type returns false" do
      refute Helpers.is_base_type?({:tuple, [:number]})
    end

    test "arbitrary atom returns false" do
      refute Helpers.is_base_type?(:foobar)
    end
  end

  # --- op_type_rel/3 ---

  describe "op_type_rel/3" do
    test "arithmetic ops with numbers" do
      for op <- [:+, :-, :*, :/] do
        assert {:ok, :number} = Helpers.op_type_rel(op, :number, :number)
      end
    end

    test "arithmetic with non-number" do
      assert :error = Helpers.op_type_rel(:+, :number, :binary)
      assert :error = Helpers.op_type_rel(:-, :binary, :number)
    end

    test "string concat both binary" do
      assert {:ok, :binary} = Helpers.op_type_rel(:<>, :binary, :binary)
    end

    test "string concat non-binary" do
      assert :error = Helpers.op_type_rel(:<>, :binary, :number)
    end

    test "boolean ops with booleans" do
      assert {:ok, :boolean} = Helpers.op_type_rel(:and, :boolean, :boolean)
      assert {:ok, :boolean} = Helpers.op_type_rel(:or, :boolean, :boolean)
    end

    test "boolean op with non-boolean" do
      assert :error = Helpers.op_type_rel(:and, :number, :boolean)
    end

    test "comparison ops return boolean" do
      for op <- [:<, :>, :<=, :>=] do
        assert {:ok, :boolean} = Helpers.op_type_rel(op, :number, :number)
      end
    end

    test "comparison with non-number" do
      assert :error = Helpers.op_type_rel(:<, :binary, :number)
    end

    test "equality same type returns boolean" do
      assert {:ok, :boolean} = Helpers.op_type_rel(:==, :number, :number)
      assert {:ok, :boolean} = Helpers.op_type_rel(:!=, :atom, :atom)
    end

    test "equality different types returns error" do
      assert :error = Helpers.op_type_rel(:==, :number, :binary)
    end

    test "unknown operator returns error" do
      assert :error = Helpers.op_type_rel(:xor, :boolean, :boolean)
    end
  end

  # --- ast_to_literal/1 ---

  describe "ast_to_literal/1" do
    test "variable AST extracts atom name" do
      assert {:ok, :my_var} = Helpers.ast_to_literal({:my_var, [line: 1], nil})
    end

    test "number literal" do
      assert {:ok, 42} = Helpers.ast_to_literal(42)
    end

    test "binary literal" do
      assert {:ok, "hello"} = Helpers.ast_to_literal("hello")
    end

    test "boolean literal" do
      assert {:ok, true} = Helpers.ast_to_literal(true)
      assert {:ok, false} = Helpers.ast_to_literal(false)
    end

    test "nil literal" do
      assert {:ok, nil} = Helpers.ast_to_literal(nil)
    end

    test "bare atom literal" do
      assert {:ok, :ok} = Helpers.ast_to_literal(:ok)
    end

    test "complex AST returns error" do
      assert :error = Helpers.ast_to_literal([1, 2])
    end
  end

  # --- get_literal_type/1 ---

  describe "get_literal_type/1" do
    test "nil returns nil type" do
      assert {:ok, nil} = Helpers.get_literal_type(nil)
    end

    test "boolean returns :boolean" do
      assert {:ok, :boolean} = Helpers.get_literal_type(true)
      assert {:ok, :boolean} = Helpers.get_literal_type(false)
    end

    test "number returns :number" do
      assert {:ok, :number} = Helpers.get_literal_type(42)
      assert {:ok, :number} = Helpers.get_literal_type(3.14)
    end

    test "binary returns :binary" do
      assert {:ok, :binary} = Helpers.get_literal_type("hello")
    end

    test "atom returns :atom" do
      assert {:ok, :atom} = Helpers.get_literal_type(:hello)
    end

    test "non-literal returns error" do
      assert :error = Helpers.get_literal_type([1, 2])
    end
  end

  # --- check_and_merge_bindings/5 ---

  describe "check_and_merge_bindings/5" do
    test "disjoint bindings merge" do
      assert {:ok, %{x: :number, y: :binary}, %{x: :number, y: :binary}} =
               Helpers.check_and_merge_bindings(@module, @meta, %{x: :number}, %{y: :binary}, %{})
    end

    test "empty bindings" do
      assert {:ok, %{}, %{z: :atom}} =
               Helpers.check_and_merge_bindings(@module, @meta, %{}, %{}, %{z: :atom})
    end

    test "conflicting variable returns error" do
      assert {:error, msg, %{}} =
               Helpers.check_and_merge_bindings(
                 @module,
                 @meta,
                 %{x: :number},
                 %{x: :binary},
                 %{}
               )

      assert %Maty.Typechecker.Error{
               category: :pattern_matching,
               kind: :conflicting_pattern_bindings
             } = msg
    end

    test "merges into existing env" do
      assert {:ok, %{x: :number}, %{x: :number, z: :atom}} =
               Helpers.check_and_merge_bindings(@module, @meta, %{x: :number}, %{}, %{z: :atom})
    end
  end

  # --- extract_meta_from_pattern/1 and extract_meta_from_ast/1 ---

  describe "extract_meta_from_pattern/1" do
    test "first element has meta" do
      assert [line: 5] =
               Helpers.extract_meta_from_pattern({{:x, [line: 5], nil}, {:y, [line: 6], nil}})
    end

    test "first element no meta, falls back to second" do
      assert [line: 6] = Helpers.extract_meta_from_pattern({42, {:y, [line: 6], nil}})
    end

    test "neither has meta" do
      assert [] = Helpers.extract_meta_from_pattern({42, "hello"})
    end
  end

  describe "extract_meta_from_ast/1" do
    test "variable AST returns meta" do
      assert [line: 3] = Helpers.extract_meta_from_ast({:x, [line: 3], nil})
    end

    test "bare literal returns empty" do
      assert [] = Helpers.extract_meta_from_ast(42)
    end
  end

  # --- join_types/2 ---

  describe "join_types/2" do
    test "bottom left" do
      assert :number = Helpers.join_types(:no_return, :number)
    end

    test "bottom right" do
      assert :binary = Helpers.join_types(:binary, :no_return)
    end

    test "same types" do
      assert :number = Helpers.join_types(:number, :number)
    end

    test "different types" do
      assert :error = Helpers.join_types(:number, :binary)
    end

    test "both bottom" do
      assert :no_return = Helpers.join_types(:no_return, :no_return)
    end
  end

  # --- join_session_types/2 ---

  describe "join_session_types/2" do
    test "SBottom left" do
      assert @st_end = Helpers.join_session_types(%SBottom{reason: :done}, @st_end)
    end

    test "SBottom right" do
      assert @st_end = Helpers.join_session_types(@st_end, %SBottom{reason: :done})
    end

    test "same types" do
      assert @st_end = Helpers.join_session_types(@st_end, @st_end)
    end

    test "different types" do
      assert :error = Helpers.join_session_types(@st_end, @st_out)
    end

    test "both SBottom" do
      sb = %SBottom{reason: :done}
      assert ^sb = Helpers.join_session_types(sb, sb)
    end
  end

  # --- check_st_unchanged/3 ---

  describe "check_st_unchanged/3" do
    test "same state returns :ok" do
      assert :ok = Helpers.check_st_unchanged(@st_end, @st_end, @meta)
    end

    test "changed state returns error" do
      assert {:error, msg} = Helpers.check_st_unchanged(@st_end, @st_out, @meta)

      assert %Maty.Typechecker.Error{
               category: :protocol_violation,
               kind: :case_scrutinee_altered_state
             } = msg
    end
  end

  # --- join_branch_results/1 ---

  describe "join_branch_results/1" do
    test "empty list returns bottom" do
      assert {:ok, {:no_return, %SBottom{reason: :nothing}}} = Helpers.join_branch_results([])
    end

    test "single result passes through" do
      assert {:ok, {:number, @st_end}} = Helpers.join_branch_results([{:number, @st_end}])
    end

    test "compatible results: bottom + value" do
      sb = %SBottom{reason: :done}

      assert {:ok, {:number, @st_end}} =
               Helpers.join_branch_results([{:no_return, sb}, {:number, @st_end}])
    end

    test "incompatible types returns error" do
      assert {:error, [t1: :number, t2: :binary]} =
               Helpers.join_branch_results([{:number, @st_end}, {:binary, @st_end}])
    end

    test "incompatible session types returns error" do
      assert {:error, [q1: @st_end, q2: @st_out]} =
               Helpers.join_branch_results([{:number, @st_end}, {:number, @st_out}])
    end

    test "incompatible in both type and session reports both pairs" do
      assert {:error, [t1: :number, t2: :binary, q1: @st_end, q2: @st_out]} =
               Helpers.join_branch_results([{:number, @st_end}, {:binary, @st_out}])
    end
  end

  # --- check_message_structure/3 ---

  describe "check_message_structure/3" do
    test "valid tagged tuple" do
      payload_ast = {:x, @meta, nil}

      assert {:ok, {:ping, ^payload_ast}} =
               Helpers.check_message_structure(@ctx, @meta, {:ping, payload_ast})
    end

    test "non-tuple message returns error" do
      assert {:error, msg} = Helpers.check_message_structure(@ctx, @meta, 42)

      assert %Maty.Typechecker.Error{
               category: :type_mismatch,
               kind: :send_message_not_tuple
             } = msg
    end
  end

  # --- find_matching_branch/2 ---

  describe "find_matching_branch/2" do
    setup do
      branch_ping = %ST.SBranch{label: :ping, payload: :number, continue_as: @st_end}
      branch_pong = %ST.SBranch{label: :pong, payload: :binary, continue_as: @st_end}
      %{branches: [branch_ping, branch_pong], branch_ping: branch_ping, branch_pong: branch_pong}
    end

    test "matching label and payload", %{branches: branches, branch_ping: branch_ping} do
      assert {:ok, ^branch_ping} = Helpers.find_matching_branch(branches, {:ping, :number})
    end

    test "label mismatch", %{branches: branches} do
      assert {:error, :label_mismatch} =
               Helpers.find_matching_branch(branches, {:unknown, :number})
    end

    test "payload mismatch", %{branches: branches} do
      assert {:error, :payload_mismatch} =
               Helpers.find_matching_branch(branches, {:ping, :binary})
    end

    test "matches second branch", %{branches: branches, branch_pong: branch_pong} do
      assert {:ok, ^branch_pong} = Helpers.find_matching_branch(branches, {:pong, :binary})
    end
  end

  # --- check_handler_type/1 ---

  describe "check_handler_type/1" do
    test "message handler" do
      assert :ok = Helpers.check_handler_type(:maty_handler_msg)
    end

    test "init handler" do
      assert :ok = Helpers.check_handler_type(:maty_handler_init)
    end

    test "other type" do
      assert {:error, :not_a_handler} = Helpers.check_handler_type(:number)
    end
  end

  # --- check_maty_state_type/1 ---

  describe "check_maty_state_type/1" do
    test "valid maty_actor_state type" do
      state_type = Type.maty_actor_state()
      assert {:ok, ^state_type} = Helpers.check_maty_state_type(state_type)
    end

    test "non-state type returns error" do
      assert {:error, %Maty.Typechecker.Error.Internal{title: "Invalid Maty State Type"}} =
               Helpers.check_maty_state_type(:number)
    end
  end

  # --- extract_capture_fun_id/1 ---

  describe "extract_capture_fun_id/1" do
    test "remote capture &Mod.fun/arity" do
      ast = {:&, [], [{:/, [], [{{:., [], [String, :length]}, [], []}, 1]}]}
      assert {:ok, {:length, 1}} = Helpers.extract_capture_fun_id(ast)
    end

    test "local capture &fun/arity" do
      ast = {:&, [], [{:/, [], [:my_fun, 2]}]}
      assert {:ok, {:my_fun, 2}} = Helpers.extract_capture_fun_id(ast)
    end

    test "non-capture returns error" do
      assert :error = Helpers.extract_capture_fun_id(42)
    end
  end

  # --- contains_register_call?/1 ---

  describe "contains_register_call?/1" do
    test "AST with register call" do
      ast = {{:., [], [Maty.DSL, :register]}, [], [:ap, :role, [], :state]}
      assert Helpers.contains_register_call?(ast)
    end

    test "AST without register call" do
      ast = {:+, [], [1, 2]}
      refute Helpers.contains_register_call?(ast)
    end

    test "nested register call" do
      register = {{:., [], [Maty.DSL, :register]}, [], [:ap, :role, [], :state]}
      ast = {:__block__, [], [42, register]}
      assert Helpers.contains_register_call?(ast)
    end
  end
end
