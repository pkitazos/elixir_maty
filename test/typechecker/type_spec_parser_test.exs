defmodule Maty.Typechecker.TypeSpecParserTest do
  use ExUnit.Case

  alias Maty.Typechecker.TypeSpecParser
  alias Maty.Types.T, as: Type

  @meta [line: 0]

  defp type_ast(name), do: {name, @meta, []}

  # --- Literal types ---

  describe "parse/1 literals" do
    test "nil" do
      assert {:ok, nil} = TypeSpecParser.parse(nil)
    end

    test "atom :ok" do
      assert {:ok, :ok} = TypeSpecParser.parse(:ok)
    end

    test "atom :error" do
      assert {:ok, :error} = TypeSpecParser.parse(:error)
    end
  end

  # --- Zero-arity known types ---

  describe "parse/1 zero-arity types" do
    test "atom" do
      assert {:ok, :atom} = TypeSpecParser.parse(type_ast(:atom))
    end

    test "number" do
      assert {:ok, :number} = TypeSpecParser.parse(type_ast(:number))
    end

    test "binary" do
      assert {:ok, :binary} = TypeSpecParser.parse(type_ast(:binary))
    end

    test "boolean" do
      assert {:ok, :boolean} = TypeSpecParser.parse(type_ast(:boolean))
    end

    test "pid" do
      assert {:ok, :pid} = TypeSpecParser.parse(type_ast(:pid))
    end

    test "ref" do
      assert {:ok, :ref} = TypeSpecParser.parse(type_ast(:ref))
    end

    test "no_return" do
      assert {:ok, :no_return} = TypeSpecParser.parse(type_ast(:no_return))
    end

    test "any" do
      assert {:ok, :any} = TypeSpecParser.parse(type_ast(:any))
    end

    test "map" do
      assert {:ok, :map} = TypeSpecParser.parse(type_ast(:map))
    end
  end

  # --- Error cases ---

  describe "parse/1 errors" do
    test "unknown type constructor" do
      assert {:error, %Maty.Typechecker.Error.Internal{title: "Unknown Type Constructor"}} =
               TypeSpecParser.parse(type_ast(:foo))
    end

    test "unsupported AST format" do
      assert {:error, %Maty.Typechecker.Error.Internal{title: "Unsupported Type Constructor"}} =
               TypeSpecParser.parse(123)
    end
  end

  # --- Tuple types ---

  describe "parse/1 tuples" do
    test "2-tuple" do
      ast = {type_ast(:number), type_ast(:binary)}
      assert {:ok, {:tuple, [:number, :binary]}} = TypeSpecParser.parse(ast)
    end

    test "n-tuple (3-tuple)" do
      ast = {:{}, @meta, [type_ast(:number), type_ast(:binary), type_ast(:atom)]}
      assert {:ok, {:tuple, [:number, :binary, :atom]}} = TypeSpecParser.parse(ast)
    end

    test "nested tuple" do
      inner = {type_ast(:binary), type_ast(:atom)}
      ast = {type_ast(:number), inner}
      assert {:ok, {:tuple, [:number, {:tuple, [:binary, :atom]}]}} = TypeSpecParser.parse(ast)
    end
  end

  # --- List types ---

  describe "parse/1 lists" do
    test "homogeneous list" do
      ast = {:list, @meta, [type_ast(:number)]}
      assert {:ok, {:list, :number}} = TypeSpecParser.parse(ast)
    end

    test "heterogeneous list returns error" do
      ast = {:list, @meta, [type_ast(:number), type_ast(:binary)]}

      assert {:error, %Maty.Typechecker.Error.Internal{title: "Heterogeneous List Type"}} =
               TypeSpecParser.parse(ast)
    end
  end

  # --- Special types ---

  describe "parse/1 special types" do
    test "Date.t()" do
      ast = {{:., @meta, [{:__aliases__, @meta, [:Date]}, :t]}, @meta, []}
      assert {:ok, :date} = TypeSpecParser.parse(ast)
    end

    test "maty_actor_state" do
      expected = Type.maty_actor_state()
      assert {:ok, ^expected} = TypeSpecParser.parse(type_ast(:maty_actor_state))
    end

    test "session" do
      expected = Type.session()
      assert {:ok, ^expected} = TypeSpecParser.parse(type_ast(:session))
    end

    test "session_ctx" do
      expected = Maty.Types.map()[:session_ctx]
      assert {:ok, ^expected} = TypeSpecParser.parse(type_ast(:session_ctx))
    end

    test "role" do
      assert {:ok, :atom} = TypeSpecParser.parse(type_ast(:role))
    end

    test "session_id" do
      assert {:ok, :ref} = TypeSpecParser.parse(type_ast(:session_id))
    end
  end
end
