defmodule Maty.Typechecker.TypeSpecParserTest do
  use ExUnit.Case

  alias Maty.Typechecker.TypeSpecParser, as: TSP
  alias Maty.Typechecker.Error.Cause
  alias Maty.Types.T, as: Type

  @meta [line: 0]

  defp type_ast(name), do: {name, @meta, []}

  # -- Literal types

  test "literals" do
    assert {:ok, nil} = TSP.parse(nil)
    assert {:ok, :ok} = TSP.parse(:ok)
    assert {:ok, :error} = TSP.parse(:error)
  end

  test "basic types" do
    for t <- [:atom, :number, :binary, :boolean, :pid, :ref, :no_return] do
      assert {:ok, ^t} = TSP.parse(type_ast(t))
    end

    date_ast = {{:., @meta, [{:__aliases__, @meta, [:Date]}, :t]}, @meta, []}
    assert {:ok, :date} = TSP.parse(date_ast)

    state = Type.maty_actor_state()
    assert {:ok, ^state} = TSP.parse(type_ast(:maty_actor_state))

    session_ctx = Type.session_ctx()
    assert {:ok, ^session_ctx} = TSP.parse(type_ast(:session_ctx))
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
  end

  # -- Map record types

  test "map records" do
    assert {:ok, {:map_record, %{}}} = TSP.parse(quote(do: %{}))

    assert {:ok, {:map_record, %{name: :binary, age: :number}}} =
             TSP.parse(quote(do: %{name: binary(), age: number()}))

    assert {:ok, {:map_record, %{user: {:map_record, %{name: :binary}}}}} =
             TSP.parse(quote(do: %{user: %{name: binary()}}))
  end

  # todo: add Map dictionary types here

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

    # no heterogeneous lists
    assert {:error, %Cause{kind: :heterogeneous_list}} =
             TSP.parse(quote(do: list(number(), binary())))

    # map records only take literal atom keys, each at most once
    for ast <- [
          quote(do: %{required(:name) => binary()}),
          quote(do: %{optional(:name) => binary()}),
          quote(do: %{"name" => binary()}),
          quote(do: %{atom() => binary()}),
          quote(do: %{name: binary(), name: number()})
        ] do
      assert {:error, %Cause{kind: :unsupported_type_constructor}} = TSP.parse(ast)
    end
  end
end
