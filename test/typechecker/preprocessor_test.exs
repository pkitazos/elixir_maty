defmodule Maty.Typechecker.PreprocessorTest do
  use ExUnit.Case

  alias Maty.Typechecker.Preprocessor
  alias Maty.Typechecker.Error

  @meta [line: 0]
  @module MyTestModule

  defp type_ast(name), do: {name, @meta, []}

  defp unsupported_ast, do: {:unsupported_garbage, @meta, [:with, :args]}

  defp spec_attr(spec_name, args_asts, return_ast) do
    [{:spec, {:"::", @meta, [{spec_name, @meta, args_asts}, return_ast]}, @module}]
  end

  # --- parse_spec_args ---

  describe "parse_spec_args/1" do
    test "happy path - all args parse successfully" do
      asts = [type_ast(:atom), type_ast(:binary)]
      assert {:ok, [:atom, :binary]} = Preprocessor.parse_spec_args(asts)
    end

    test "empty arg list" do
      assert {:ok, []} = Preprocessor.parse_spec_args([])
    end

    test "single bad arg" do
      asts = [type_ast(:atom), unsupported_ast()]
      assert {:error, {1, %Error.Internal{}}} = Preprocessor.parse_spec_args(asts)
    end

    test "first arg bad - index is 0" do
      asts = [unsupported_ast(), type_ast(:atom)]
      assert {:error, {0, %Error.Internal{}}} = Preprocessor.parse_spec_args(asts)
    end

    test "multiple bad args - returns first" do
      asts = [unsupported_ast(), unsupported_ast()]
      assert {:error, {0, %Error.Internal{}}} = Preprocessor.parse_spec_args(asts)
    end
  end

  # --- validate_type_annotation ---

  describe "validate_type_annotation/3" do
    test "happy path - spec matches function, args and return parse" do
      attr = spec_attr(:my_func, [type_ast(:atom), type_ast(:binary)], type_ast(:number))

      assert {:ok, {[:atom, :binary], :number}} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 2})
    end

    test "spec name/arity mismatch" do
      attr = spec_attr(:other_func, [type_ast(:atom)], type_ast(:binary))

      assert {:error, error} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 1})

      assert error =~ "Spec Mismatch"
      assert error =~ "other_func"
      assert error =~ "my_func"
    end

    test "arg parse failure - regression test for Bug 1" do
      attr = spec_attr(:my_func, [type_ast(:atom), unsupported_ast()], type_ast(:binary))

      assert {:error, error} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 2})

      assert error =~ "Invalid Spec Argument"
      assert error =~ "#2"
    end

    test "return type parse failure" do
      attr = spec_attr(:my_func, [type_ast(:atom)], unsupported_ast())

      assert {:error, error} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 1})

      assert error =~ "Invalid Spec Return Type"
    end

    test "no spec attribute" do
      assert :no_spec = Preprocessor.validate_type_annotation(nil, @module, {:my_func, 1})
    end

    test "tuple return type" do
      attr = spec_attr(:my_func, [type_ast(:atom)], {type_ast(:atom), type_ast(:number)})

      assert {:ok, {[:atom], {:tuple, [:atom, :number]}}} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 1})
    end

    test "zero-arg function" do
      attr = spec_attr(:my_func, [], type_ast(:atom))

      assert {:ok, {[], :atom}} =
               Preprocessor.validate_type_annotation(attr, @module, {:my_func, 0})
    end
  end

  # --- validate_handler_annotation ---

  describe "validate_handler_annotation/3" do
    test "happy path - label exists, returns session type" do
      st = %ST.SEnd{}
      session_types = %{ping: st}

      assert {:ok, ^st} =
               Preprocessor.validate_handler_annotation(:ping, session_types, @meta)
    end

    test "missing handler label" do
      session_types = %{}

      assert {:error, error} =
               Preprocessor.validate_handler_annotation(:ping, session_types, @meta)

      assert error =~ "ping"
    end

    test "label with string session type passes through" do
      session_types = %{ping: "+Client:{Ping(number).end}"}

      assert {:ok, st_string} =
               Preprocessor.validate_handler_annotation(:ping, session_types, @meta)

      assert is_binary(st_string)
    end
  end
end
