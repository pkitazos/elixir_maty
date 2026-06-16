defmodule Maty.Typechecker.PatternBindingTest do
  use ExUnit.Case

  alias Maty.Typechecker.{PatternBinding, Ctx, Error}

  @meta [line: 0]
  @ctx %Ctx{module: TestModule, meta: @meta}

  defp var(name), do: {name, @meta, nil}

  # --- Pat-Var ---

  describe "tc_pattern/4 variable patterns" do
    test "variable binds to expected type" do
      assert {:ok, %{x: :number}, %{x: :number}} =
               PatternBinding.tc_pattern(@ctx, var(:x), :number, %{})
    end

    test "adds to existing env" do
      assert {:ok, %{y: :binary}, %{x: :number, y: :binary}} =
               PatternBinding.tc_pattern(@ctx, var(:y), :binary, %{x: :number})
    end

    test "overwrites existing binding" do
      assert {:ok, %{x: :binary}, %{x: :binary}} =
               PatternBinding.tc_pattern(@ctx, var(:x), :binary, %{x: :number})
    end
  end

  # --- Pat-Wild ---

  describe "tc_pattern/4 wildcard patterns" do
    test "bare atom :_ binds nothing" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, :_, :number, %{})
    end

    test "underscore AST binds nothing" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, {:_, @meta, nil}, :number, %{})
    end

    test "wildcard preserves existing env" do
      env = %{x: :binary}
      assert {:ok, %{}, ^env} = PatternBinding.tc_pattern(@ctx, :_, :number, env)
    end
  end

  # --- Pat-Value ---

  describe "tc_pattern/4 literal patterns" do
    test "number matches :number" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, 42, :number, %{})
    end

    test "binary matches :binary" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, "hello", :binary, %{})
    end

    test "boolean matches :boolean" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, true, :boolean, %{})
    end

    test "atom literal matches :atom" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, :hello, :atom, %{})
    end

    test "atom literal also matches other expected types" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, :hello, :binary, %{})
    end

    test "number vs binary mismatch" do
      assert {:error, msg, %{}} = PatternBinding.tc_pattern(@ctx, 42, :binary, %{})
      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end

  # --- Pat-EmptyList ---

  describe "tc_pattern/4 empty list" do
    test "matches list type" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, [], {:list, :number}, %{})
    end

    test "matches :any" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, [], :any, %{})
    end

    test "fails against non-list type" do
      assert {:error, msg, %{}} = PatternBinding.tc_pattern(@ctx, [], :number, %{})
      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end

  # --- Pat-EmptyTuple ---

  describe "tc_pattern/4 empty tuple" do
    test "matches empty tuple type" do
      assert {:ok, %{}, %{}} =
               PatternBinding.tc_pattern(@ctx, {:{}, @meta, []}, {:tuple, []}, %{})
    end

    test "matches :any" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, {:{}, @meta, []}, :any, %{})
    end

    test "fails against non-tuple type" do
      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(@ctx, {:{}, @meta, []}, :number, %{})

      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end

  # --- Pat-EmptyMap ---

  describe "tc_pattern/4 empty map" do
    test "matches map type" do
      assert {:ok, %{}, %{}} =
               PatternBinding.tc_pattern(@ctx, {:%{}, @meta, []}, {:map, %{x: :number}}, %{})
    end

    test "matches :any" do
      assert {:ok, %{}, %{}} = PatternBinding.tc_pattern(@ctx, {:%{}, @meta, []}, :any, %{})
    end

    test "fails against non-map type" do
      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(@ctx, {:%{}, @meta, []}, :number, %{})

      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end

  # --- Pat-Cons ---

  describe "tc_pattern/4 cons [h|t] patterns" do
    test "binds head and tail variables" do
      pattern = {:|, @meta, [var(:h), var(:t)]}

      assert {:ok, %{h: :number, t: {:list, :number}}, %{h: :number, t: {:list, :number}}} =
               PatternBinding.tc_pattern(@ctx, pattern, {:list, :number}, %{})
    end

    test "fails against non-list type" do
      pattern = {:|, @meta, [var(:h), var(:t)]}
      assert {:error, msg, %{}} = PatternBinding.tc_pattern(@ctx, pattern, :number, %{})
      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end

    test "wildcard head" do
      pattern = {:|, @meta, [:_, var(:t)]}

      assert {:ok, %{t: {:list, :binary}}, %{t: {:list, :binary}}} =
               PatternBinding.tc_pattern(@ctx, pattern, {:list, :binary}, %{})
    end
  end

  # --- Pat-Tuple (2-tuple) ---

  describe "tc_pattern/4 2-tuple patterns" do
    test "two variables bind correctly" do
      pattern = {var(:a), var(:b)}

      assert {:ok, %{a: :number, b: :binary}, %{a: :number, b: :binary}} =
               PatternBinding.tc_pattern(@ctx, pattern, {:tuple, [:number, :binary]}, %{})
    end

    test "fails against non-tuple type" do
      pattern = {var(:a), var(:b)}
      assert {:error, msg, %{}} = PatternBinding.tc_pattern(@ctx, pattern, :number, %{})
      assert %Error{category: :pattern_matching, kind: :pattern_not_tuple} = msg
    end

    test "fails with wrong arity" do
      pattern = {var(:a), var(:b)}

      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:tuple, [:number, :binary, :atom]},
                 %{}
               )

      assert %Error{category: :pattern_matching, kind: :tuple_arity_mismatch} = msg
    end

    test "nested tuple" do
      inner_pattern = {var(:b), var(:c)}
      pattern = {var(:a), inner_pattern}

      assert {:ok, bindings, env} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:tuple, [:number, {:tuple, [:binary, :atom]}]},
                 %{}
               )

      assert bindings[:a] == :number
      assert bindings[:b] == :binary
      assert bindings[:c] == :atom
      assert env == %{a: :number, b: :binary, c: :atom}
    end
  end

  # --- Pat-Tuple (n-tuple) ---

  describe "tc_pattern/4 n-tuple patterns" do
    test "3-tuple binds all elements" do
      pattern = {:{}, @meta, [var(:a), var(:b), var(:c)]}

      assert {:ok, bindings, env} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:tuple, [:number, :binary, :atom]},
                 %{}
               )

      assert bindings == %{a: :number, b: :binary, c: :atom}
      assert env == %{a: :number, b: :binary, c: :atom}
    end

    test "arity mismatch" do
      pattern = {:{}, @meta, [var(:a), var(:b)]}

      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:tuple, [:number, :binary, :atom]},
                 %{}
               )

      assert %Error{category: :pattern_matching, kind: :pattern_arity_mismatch} = msg
    end

    test "non-tuple expected type" do
      pattern = {:{}, @meta, [var(:a)]}

      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(@ctx, pattern, :number, %{})

      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end

  # --- Pat-Map ---

  describe "tc_pattern/4 map patterns" do
    test "atom keys bind values" do
      pattern = {:%{}, @meta, [{:name, var(:n)}]}

      assert {:ok, %{n: :binary}, %{n: :binary}} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:map, %{name: :binary}},
                 %{}
               )
    end

    test "key not found in expected map" do
      pattern = {:%{}, @meta, [{:missing, var(:x)}]}

      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:map, %{name: :binary}},
                 %{}
               )

      assert %Error{category: :pattern_matching, kind: :pattern_map_key_not_found} = msg
    end

    test "multiple keys all matching" do
      pattern = {:%{}, @meta, [{:name, var(:n)}, {:age, var(:a)}]}

      assert {:ok, bindings, env} =
               PatternBinding.tc_pattern(
                 @ctx,
                 pattern,
                 {:map, %{name: :binary, age: :number}},
                 %{}
               )

      assert bindings[:n] == :binary
      assert bindings[:a] == :number
      assert env == %{n: :binary, a: :number}
    end

    test "non-map expected type" do
      pattern = {:%{}, @meta, [{:k, var(:v)}]}

      assert {:error, msg, %{}} =
               PatternBinding.tc_pattern(@ctx, pattern, :number, %{})

      assert %Error{category: :pattern_matching, kind: :pattern_type_mismatch} = msg
    end
  end
end
