defmodule Maty.Typechecker.TypeSpecParserTest do
  use ExUnit.Case

  alias Maty.Typechecker.TypeSpecParser, as: TSP
  alias Maty.Typechecker.Error.Cause

  @meta [line: 0]

  defp type_ast(name), do: {name, @meta, []}

  # -- Literal types

  test "literals" do
    assert {:ok, nil} = TSP.parse(nil)
    assert {:ok, :ok} = TSP.parse(:ok)
    assert {:ok, :error} = TSP.parse(:error)
  end

  test "basic types" do
    for t <- [:atom, :number, :binary, :boolean, :pid, :reference, :no_return] do
      assert {:ok, ^t} = TSP.parse(type_ast(t))
    end
  end

  test "tuples" do
    assert {:ok, {:tuple, [:number, :binary]}} =
             TSP.parse(quote(do: {number(), binary()}))

    assert {:ok, {:tuple, [:number, :binary, :atom]}} =
             TSP.parse(quote(do: {number(), binary(), atom()}))

    assert {:ok, {:tuple, [:number, {:tuple, [:binary, :atom]}]}} =
             TSP.parse(quote(do: {number(), {binary(), atom()}}))
  end

  test "lists" do
    assert {:ok, {:list, :number}} = TSP.parse(quote(do: list(number())))
    assert {:ok, {:list, :number}} = TSP.parse(quote(do: [number()]))
    assert {:ok, {:list, {:list, :binary}}} = TSP.parse(quote(do: [[binary()]]))
  end

  # -- Map record types

  test "map records" do
    assert {:ok, {:map_record, %{name: :binary, age: :number}}} =
             TSP.parse(quote(do: %{name: binary(), age: number()}))

    assert {:ok, {:map_record, %{user: {:map_record, %{name: :binary}}}}} =
             TSP.parse(quote(do: %{user: %{name: binary()}}))
  end

  # -- Map dictionary types

  test "map dictionaries" do
    assert {:ok, {:map_dict, {:atom, :binary}}} = TSP.parse(quote(do: %{atom() => binary()}))

    assert {:ok, {:map_dict, {:binary, {:list, :number}}}} =
             TSP.parse(quote(do: %{binary() => list(number())}))
  end

  # -- Function types

  test "function types" do
    assert {:ok, {:function, [], :binary}} = TSP.parse(quote(do: (-> binary())))
    assert {:ok, {:function, [:number], :binary}} = TSP.parse(quote(do: (number() -> binary())))

    assert {:ok, {:function, [:number, :atom], :binary}} =
             TSP.parse(quote(do: (number(), atom() -> binary())))

    assert {:ok, {:function, [{:function, [:number], :binary}], :atom}} =
             TSP.parse(quote(do: ((number() -> binary()) -> atom())))
  end

  # -- Error cases

  test "unsupported specs are rejected" do
    # `any()` and `map()` are not types, since there is no subtyping
    for ast <- [
          quote(do: foo()),
          quote(do: any()),
          quote(do: map()),
          quote(do: list()),
          # ^ should not be allowed
          quote(do: function()),
          # ^ should not be allowed
          quote(do: %{name: wat()})
        ] do
      assert {:error, %Cause{kind: :unknown_type_constructor}} = TSP.parse(ast)
    end

    # no num literals
    assert {:error, %Cause{kind: :unsupported_type_constructor}} =
             TSP.parse(123)

    # a function type has a single arrow
    assert {:error, %Cause{kind: :unsupported_type_constructor}} =
             TSP.parse(
               quote(
                 do: (
                   number() -> binary()
                   atom() -> binary()
                 )
               )
             )

    # list types name exactly one element type
    for ast <- [
          quote(do: list(number(), binary())),
          quote(do: list(number(), number())),
          quote(do: []),
          quote(do: [number(), ...]),
          quote(do: [number(), binary()])
        ] do
      assert {:error, %Cause{kind: :unsupported_type_constructor}} = TSP.parse(ast)
    end

    # map records only take literal atom keys, each at most once
    for ast <- [
          quote(do: %{required(:name) => binary()}),
          quote(do: %{optional(:name) => binary()}),
          quote(do: %{"name" => binary()}),
          quote(do: %{name: binary(), name: number()})
        ] do
      assert {:error, %Cause{kind: :unsupported_type_constructor}} = TSP.parse(ast)
    end

    # a record has at least one field
    assert {:error, %Cause{kind: :empty_record}} = TSP.parse(quote(do: %{}))

    # a dictionary has a single entry, whose key is a base type
    assert {:error, %Cause{kind: :unsupported_type_constructor}} =
             TSP.parse(quote(do: %{atom() => binary(), binary() => number()}))

    assert {:error, %Cause{kind: :dict_key_not_base_type}} =
             TSP.parse(quote(do: %{list(number()) => binary()}))
  end
end
