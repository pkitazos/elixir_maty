defmodule Maty.Typechecker.HelpersTest do
  use ExUnit.Case

  alias Maty.Typechecker.Helpers
  alias Maty.ST.SBottom

  @meta [line: 0]
  @module TestModule
  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)

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
               kind: :conflicting_pattern_bindings,
               details: %{conflicting_vars: [:x]}
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

  # --- contains_register_call?/1 ---

  describe "contains_register_call?/1" do
    test "AST with register call" do
      ast = {{:., [], [Maty.Runtime, :register]}, [], [:ap, :role, [], :state]}
      assert Helpers.contains_register_call?(ast)
    end

    test "AST without register call" do
      ast = {:+, [], [1, 2]}
      refute Helpers.contains_register_call?(ast)
    end

    test "nested register call" do
      register = {{:., [], [Maty.Runtime, :register]}, [], [:ap, :role, [], :state]}
      ast = {:__block__, [], [42, register]}
      assert Helpers.contains_register_call?(ast)
    end
  end
end
