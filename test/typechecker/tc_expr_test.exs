defmodule Maty.Typechecker.TCExprTest do
  use ExUnit.Case

  alias Maty.Typechecker.{TC, Ctx, Error}

  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)
  @st_in ST.input_one(:client, :msg, :binary, @st_end)

  @ctx %Ctx{
    module: TestModule,
    meta: [line: 0],
    signatures: %{
      {TestModule, :f, 1} => {:function, [:number], :binary},
      h: {:handler, :message, :seller, @st_in},
      i: {:handler, :init, :seller, :number, @st_out}
    }
  }

  @person {:map_record, %{name: :binary, age: :number}}

  # only forms that look the same before and after expansion are tested here,
  # the ones expansion rewrites (operators, `and` / `or`, strings, `send`) are tested in `compile_error_test.exs`
  #
  # variables in code expanded by the normal compilation process have a `nil` context
  # but `quote` gives them the current module as the context
  defp expr(quoted) do
    Macro.prewalk(quoted, fn
      {name, meta, context} when is_atom(name) and is_atom(context) -> {name, meta, nil}
      node -> node
    end)
  end

  defp synth(quoted, env \\ %{}, st \\ @st_end), do: TC.synth(@ctx, env, st, expr(quoted))
  defp check(quoted, t, env \\ %{}), do: TC.check(@ctx, env, @st_end, expr(quoted), t)

  defp assert_error(result, kind) do
    assert {:error, %Error{kind: ^kind} = error, _env} = result
    error
  end

  # -- TV-Const

  test "TV-Const" do
    assert {:ok, :boolean, _, _} = synth(true)
    assert {:ok, nil, _, _} = synth(nil)
    assert {:ok, :binary, _, _} = synth("hi")
    assert {:ok, :number, _, _} = synth(42)
    assert {:ok, :number, _, _} = synth(3.14)
    assert {:ok, :atom, _, _} = synth(:hello)
  end

  test "pure expressions leave the session type and env alone" do
    env = %{x: :number}

    for quoted <- [42, quote(do: x), quote(do: {x, "a"}), quote(do: [x, 1])] do
      assert {:ok, _type, @st_out, ^env} = synth(quoted, env, @st_out)
    end
  end

  # -- TV-Var

  test "TV-Var" do
    assert {:ok, :binary, _, _} = synth(quote(do: x), %{x: :binary})

    error = assert_error(synth(quote(do: missing)), :variable_not_exist)
    assert %{var: :missing} = error.details
  end

  # -- TV-Cons-Syn / TV-Nil-Syn

  test "lists" do
    assert {:ok, {:list, :number}, _, _} = synth([1, 2])
    assert {:ok, {:list, :number}, _, _} = synth(quote(do: [x, y]), %{x: :number, y: :number})

    assert_error(synth([1, "two"]), :expected)

    # an empty list has no element to infer its type from, it can only be checked
    assert_error(synth([]), :cannot_infer_type)
  end

  # -- TV-Tuple-Syn

  test "tuples" do
    assert {:ok, {:tuple, []}, _, _} = synth(quote(do: {}))
    assert {:ok, {:tuple, [:number, :binary]}, _, _} = synth(quote(do: {1, "a"}))
    assert {:ok, {:tuple, [:number, :binary, :boolean]}, _, _} = synth(quote(do: {1, "a", true}))

    assert {:ok, {:tuple, [:number, {:tuple, [:number, :number]}]}, _, _} =
             synth(quote(do: {1, {2, 3}}))

    assert {:ok, {:tuple, [:number, :binary]}, _, _} =
             synth(quote(do: {x, y}), %{x: :number, y: :binary})
  end

  # -- TV-Dict-Syn / TV-Record-Syn

  test "maps" do
    assert {:ok, @person, _, _} = synth(quote(do: %{name: "alice", age: 42}))
    assert {:ok, {:map_dict, {:binary, :number}}, _, _} = synth(quote(do: %{"a" => 1}))

    # an empty map has no entry to infer its type from, it can only be checked
    assert_error(synth(quote(do: %{})), :cannot_infer_type)
  end

  test "field access" do
    assert {:ok, :binary, _, _} = synth(quote(do: p.name), %{p: @person})

    user = {:map_record, %{address: {:map_record, %{city: :binary}}}}
    assert {:ok, :binary, _, _} = synth(quote(do: u.address.city), %{u: user})

    assert_error(synth(quote(do: n.name), %{n: :number}), :field_access_not_record)

    error = assert_error(synth(quote(do: p.email), %{p: @person}), :field_access_key_not_found)
    assert %{key: :email} = error.details
  end

  test "record update" do
    env = %{p: @person, n: :number}

    assert {:ok, @person, _, _} = synth(quote(do: %{p | name: "bob", age: 30}), env)

    assert_error(synth(quote(do: %{n | age: 30}), env), :map_update_not_record)

    error =
      assert_error(
        synth(quote(do: %{p | email: "bob@example.com"}), env),
        :map_update_key_not_found
      )

    assert %{key: :email} = error.details

    error = assert_error(synth(quote(do: %{p | age: "thirty"}), env), :expected)
    assert %{expected: :number, got: :binary} = error.details
    assert [record_field: :age] = error.trace
  end

  # -- T-Let

  test "T-Let" do
    assert {:ok, :number, _, %{x: :number}} = synth(quote(do: x = 42))

    # an existing binding is shadowed
    assert {:ok, :number, _, %{x: :number}} = synth(quote(do: x = 42), %{x: :binary})

    pair = {:tuple, [:number, :binary]}

    assert {:ok, ^pair, _, %{a: :number, b: :binary}} =
             synth(quote(do: {a, b} = pair), %{pair: pair})
  end

  test "blocks" do
    block =
      quote do
        x = 42
        y = "hello"
        {x, y}
      end

    assert {:ok, {:tuple, [:number, :binary]}, _, %{x: :number, y: :binary}} = synth(block)
  end

  # -- T-Case

  test "T-Case" do
    env = %{x: :number}

    consistent =
      quote do
        case x do
          1 -> "one"
          2 -> "two"
        end
      end

    assert {:ok, :binary, _, _} = synth(consistent, env)

    # a pattern's variables are bound in its branch
    binding =
      quote do
        case x do
          n -> n
        end
      end

    assert {:ok, :number, _, _} = synth(binding, env)

    inconsistent =
      quote do
        case x do
          1 -> "one"
          2 -> 42
        end
      end

    assert_error(synth(inconsistent, env), :case_branches_incompatible)
  end

  # -- TV-Tuple-Chk, TV-Nil, TV-Cons-Chk, TV-Record-Chk, TV-Dict-Chk, TV-Switch

  test "check mode" do
    assert {:ok, _, _, _} = check([], {:list, :number})
    assert {:ok, _, _, _} = check([1, 2], {:list, :number})
    assert {:ok, _, _, _} = check(quote(do: %{}), {:map_dict, {:atom, :number}})
    assert {:ok, _, _, _} = check(quote(do: %{name: "a", age: 1}), @person)
    assert {:ok, _, _, _} = check(quote(do: {1, "a"}), {:tuple, [:number, :binary]})

    assert {:error, _, _} = check([1, "two"], {:list, :number})
    assert {:error, _, _} = check(quote(do: %{name: "a"}), @person)
    assert {:error, _, _} = check(quote(do: {1, "a", 2}), {:tuple, [:number, :binary]})

    # TV-Switch
    assert_error(check(42, :binary), :expected)
  end

  # -- TV-MsgHandler, TV-InitHandler, function captures

  test "captures" do
    assert {:ok, {:handler, :message, :seller, @st_in}, _, _} = synth(quote(do: &h/3))
    assert {:ok, {:handler, :init, :seller, :number, @st_out}, _, _} = synth(quote(do: &i/2))
    assert {:ok, {:function, [:number], :binary}, _, _} = synth(quote(do: &f/1))

    assert_error(synth(quote(do: &h/2)), :handler_ref_wrong_arity)
    assert_error(synth(quote(do: &i/3)), :handler_ref_wrong_arity)
    assert_error(synth(quote(do: &nope/1)), :function_not_exist)
  end

  test "rejected expressions" do
    assert_error(synth(quote(do: fn x -> x end)), :unsupported_anonymous_function)

    receive_ast =
      quote do
        receive do
          msg -> msg
        end
      end

    assert_error(synth(receive_ast), :no_native_receive)

    with_ast =
      quote do
        with {:ok, x} <- y, do: x
      end

    assert_error(synth(with_ast, %{y: :number}), :unsupported_expression)
  end

  # -- TV-Abs

  # todo: fails until TV-Abs is implemented (its clause in `tc.ex` is a stub)
  test "TV-Abs" do
    fun_type = {:function, [:number], :number}
    assert {:ok, ^fun_type, _, _} = check(quote(do: fn x -> x end), fun_type)
  end

  # todo: fails until a function value can be called
  test "calling a function value" do
    assert {:ok, :binary, _, _} = synth(quote(do: g.(1)), %{g: {:function, [:number], :binary}})
  end
end
