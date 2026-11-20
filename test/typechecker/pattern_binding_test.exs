defmodule Maty.Typechecker.PatternBindingTest do
  use ExUnit.Case

  alias Maty.Typechecker.{PatternBinding, Ctx, Error}

  @meta [line: 0]
  @ctx %Ctx{module: TestModule, meta: @meta, signatures: %{}}

  defp tc(pattern, expected_type, env \\ %{}),
    do: PatternBinding.tc_pattern(@ctx, pattern, expected_type, env)

  defp assert_mismatch(pattern, expected_type, kind \\ :pattern_type_mismatch) do
    assert {:error, %Error{category: :pattern_matching, kind: ^kind} = error, _env} =
             tc(pattern, expected_type)

    error
  end

  # -- Pat-Var

  test "Pat-Var" do
    assert {:ok, %{x: :number}, %{x: :number}} = tc(quote(do: x), :number)

    assert {:ok, %{y: :binary}, %{x: :number, y: :binary}} =
             tc(quote(do: y), :binary, %{x: :number})

    # an existing binding is shadowed
    assert {:ok, %{x: :binary}, %{x: :binary}} = tc(quote(do: x), :binary, %{x: :number})
  end

  # -- Pat-Wild

  # todo: fails until `_` reaches Pat-Wild (Pat-Var comes first and binds it as a variable named `_`)
  test "Pat-Wild" do
    env = %{x: :binary}
    assert {:ok, %{}, ^env} = tc(:_, :number, env)
    assert {:ok, %{}, ^env} = tc(quote(do: _), :number, env)
  end

  # -- Pat-Value

  test "Pat-Value" do
    assert {:ok, %{}, %{}} = tc(42, :number)
    assert {:ok, %{}, %{}} = tc("hello", :binary)
    assert {:ok, %{}, %{}} = tc(true, :boolean)
    assert {:ok, %{}, %{}} = tc(:hello, :atom)
    assert {:ok, %{}, %{}} = tc(:ok, :ok)

    assert_mismatch(42, :binary)
  end

  # todo: fails until Pat-Value stops accepting an atom literal against any expected type
  test "an atom literal only matches atom or its own atom type" do
    assert_mismatch(:hello, :binary)
  end

  # -- Pat-EmptyList

  # -- Pat-EmptyTuple

  # -- Pat-EmptyMap

  test "empty collections" do
    assert {:ok, %{}, %{}} = tc([], {:list, :number})
    assert {:ok, %{}, %{}} = tc(quote(do: {}), {:tuple, []})
    assert {:ok, %{}, %{}} = tc(quote(do: %{}), {:map_record, %{x: :number}})

    assert_mismatch([], :number)
    assert_mismatch(quote(do: {}), :number)
    assert_mismatch(quote(do: %{}), :number)
  end

  # -- Pat-Cons

  # todo: fails until `[h | t]` reaches Pat-Cons (it is `[{:|, _, [h, t]}]`, a list around the cons)
  test "Pat-Cons" do
    assert {:ok, %{h: :number, t: {:list, :number}}, _env} =
             tc(quote(do: [h | t]), {:list, :number})

    assert_mismatch(quote(do: [h | t]), :number)
  end

  # todo: fails until non-empty list patterns are supported
  test "list literal patterns" do
    assert {:ok, %{a: :number, b: :number}, _env} = tc(quote(do: [a, b]), {:list, :number})

    assert {:ok, %{a: :number, b: :number, t: {:list, :number}}, _env} =
             tc(quote(do: [a, b | t]), {:list, :number})

    assert_mismatch(quote(do: [a, b]), :number)
  end

  # -- Pat-Tuple

  test "Pat-Tuple" do
    assert {:ok, %{a: :number, b: :binary}, _env} =
             tc(quote(do: {a, b}), {:tuple, [:number, :binary]})

    assert {:ok, %{a: :number, b: :binary, c: :atom}, _env} =
             tc(quote(do: {a, b, c}), {:tuple, [:number, :binary, :atom]})

    assert {:ok, %{a: :number, b: :binary, c: :atom}, _env} =
             tc(quote(do: {a, {b, c}}), {:tuple, [:number, {:tuple, [:binary, :atom]}]})

    assert_mismatch(quote(do: {a, b}), :number)
    assert_mismatch(quote(do: {a, b, c}), :number)

    # the pattern is the 2-tuple, the type is the 3-tuple
    error =
      assert_mismatch(
        quote(do: {a, b}),
        {:tuple, [:number, :binary, :atom]},
        :tuple_arity_mismatch
      )

    assert %{pattern_arity: 2, expected: 3} = error.details
  end

  # -- Pat-Map

  test "Pat-Map" do
    assert {:ok, %{n: :binary, a: :number}, _env} =
             tc(quote(do: %{name: n, age: a}), {:map_record, %{name: :binary, age: :number}})

    assert_mismatch(
      quote(do: %{missing: x}),
      {:map_record, %{name: :binary}},
      :pattern_map_key_not_found
    )

    assert_mismatch(quote(do: %{k: v}), :number)
  end

  # -- Pat-Match

  test "Pat-Match" do
    person = {:map_record, %{name: :binary, age: :number}}

    # binds the variables of both sides
    assert {:ok, bindings, env} = tc(quote(do: %{name: n} = person), person)
    assert bindings == %{n: :binary, person: person}
    assert env == %{n: :binary, person: person}

    # the variable can be on either side
    assert {:ok, %{a: :number, person: ^person}, _env} = tc(quote(do: person = %{age: a}), person)

    # both sides are checked against the expected type
    assert_mismatch(quote(do: %{missing: x} = person), person, :pattern_map_key_not_found)

    # binding the same variable on both sides is a conflict
    assert_mismatch(quote(do: %{name: x} = x), person, :conflicting_pattern_bindings)
  end
end
