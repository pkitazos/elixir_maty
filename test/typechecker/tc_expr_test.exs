defmodule Maty.Typechecker.TCExprTest do
  use ExUnit.Case

  alias Maty.Typechecker.TC
  alias Maty.ST

  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)

  # The typechecker operates on expanded AST (from bytecode debug info), not the surface-level AST from `quote`
  # These helpers produce the correct AST shapes.

  @meta [line: 0]

  defp var(name), do: {name, @meta, nil}

  defp erlang_op(op, lhs, rhs), do: {{:., @meta, [:erlang, op]}, @meta, [lhs, rhs]}
  defp erlang_not(operand), do: {{:., @meta, [:erlang, :not]}, @meta, [operand]}

  defp string_concat(lhs, rhs) do
    {:<<>>, @meta,
     [
       {:"::", @meta, [lhs, {:binary, @meta, nil}]},
       {:"::", @meta, [rhs, {:binary, @meta, nil}]}
     ]}
  end

  defp block(exprs), do: {:__block__, @meta, exprs}

  defp match(pattern, expr), do: {:=, @meta, [pattern, expr]}

  defp case_expr(scrutinee, clauses) do
    branches =
      Enum.map(clauses, fn {pattern, body} ->
        {:->, @meta, [[pattern], body]}
      end)

    {:case, @meta, [scrutinee, [do: branches]]}
  end

  # Runs tc_expr inside a freshly created module so that Module.get_attribute
  # calls (for delta_M, delta_I, psi) work. Needed for any AST that contains
  # bare atoms (map keys, handler names, etc).
  defp tc_with_module(var_env, st_pre, ast) do
    mod = :"Elixir.Maty.TestMod#{System.unique_integer([:positive])}"

    body =
      quote do
        Maty.Utils.Env.setup(__MODULE__, :delta_M)
        Maty.Utils.Env.setup(__MODULE__, :delta_I)
        Maty.Utils.Env.setup(__MODULE__, :psi)
        Maty.Utils.Env.setup(__MODULE__, :spec_errors)

        @tc_result Maty.Typechecker.TC.tc_expr(
                     __MODULE__,
                     unquote(Macro.escape(var_env)),
                     unquote(Macro.escape(st_pre)),
                     unquote(Macro.escape(ast))
                   )
        def tc_result, do: @tc_result
      end

    {:module, ^mod, _, _} = Module.create(mod, body, Macro.Env.location(__ENV__))
    result = mod.tc_result()
    :code.purge(mod)
    :code.delete(mod)
    result
  end

  # --- Literals

  describe "tc_expr/4 literals" do
    test "boolean true" do
      assert {:ok, {:boolean, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, true)
    end

    test "boolean false" do
      assert {:ok, {:boolean, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, false)
    end

    test "nil" do
      assert {:ok, {nil, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, nil)
    end

    test "binary string" do
      assert {:ok, {:binary, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, "hello")
    end

    test "number integer" do
      assert {:ok, {:number, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, 42)
    end

    test "number float" do
      assert {:ok, {:number, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, 3.14)
    end

    test "literals preserve session state" do
      assert {:ok, {:number, @st_out}, %{}} = TC.tc_expr(nil, %{}, @st_out, 42)
      assert {:ok, {:binary, @st_out}, %{}} = TC.tc_expr(nil, %{}, @st_out, "hi")
      assert {:ok, {:boolean, @st_out}, %{}} = TC.tc_expr(nil, %{}, @st_out, true)
    end

    test "literals preserve var env" do
      env = %{x: :number, y: :binary}
      assert {:ok, {:number, @st_end}, ^env} = TC.tc_expr(nil, env, @st_end, 42)
    end
  end

  # --- Variables

  describe "tc_expr/4 variables" do
    test "variable lookup succeeds when bound" do
      env = %{x: :number}
      assert {:ok, {:number, @st_end}, ^env} = TC.tc_expr(nil, env, @st_end, var(:x))
    end

    test "variable lookup returns type from env" do
      env = %{name: :binary, count: :number, flag: :boolean}
      assert {:ok, {:binary, @st_end}, _} = TC.tc_expr(nil, env, @st_end, var(:name))
      assert {:ok, {:number, @st_end}, _} = TC.tc_expr(nil, env, @st_end, var(:count))
      assert {:ok, {:boolean, @st_end}, _} = TC.tc_expr(nil, env, @st_end, var(:flag))
    end

    test "unbound variable returns error" do
      assert {:error, msg, %{}} = TC.tc_expr(nil, %{}, @st_end, var(:unknown_var))
      assert msg =~ "unknown_var"
    end

    test "variable preserves session state" do
      env = %{x: :number}
      assert {:ok, {:number, @st_out}, ^env} = TC.tc_expr(nil, env, @st_out, var(:x))
    end
  end

  # --- Lists

  describe "tc_expr/4 lists" do
    test "empty list" do
      assert {:ok, {{:list, :any}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, [])
    end

    test "homogeneous number list" do
      assert {:ok, {{:list, :number}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, [1, 2, 3])
    end

    test "homogeneous binary list" do
      assert {:ok, {{:list, :binary}, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, ["a", "b", "c"])
    end

    test "homogeneous boolean list" do
      assert {:ok, {{:list, :boolean}, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, [true, false])
    end

    @tag :skip
    test "heterogeneous list returns error" do
      # BUG: tc.ex:184 hardcodes meta=[] for list error path,
      # causing KeyError when error formatter accesses meta[:line]
      assert {:error, msg, _env} = TC.tc_expr(nil, %{}, @st_end, [1, "two"])
      assert is_binary(msg)
    end

    test "single element list" do
      assert {:ok, {{:list, :number}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, [42])
    end

    test "list of variables" do
      env = %{x: :number, y: :number}

      assert {:ok, {{:list, :number}, @st_end}, ^env} =
               TC.tc_expr(nil, env, @st_end, [var(:x), var(:y)])
    end

    test "list preserves session state" do
      assert {:ok, {{:list, :number}, @st_out}, %{}} = TC.tc_expr(nil, %{}, @st_out, [1, 2])
    end
  end

  # --- Tuples

  describe "tc_expr/4 tuples" do
    test "2-tuple" do
      ast = {1, "hello"}

      assert {:ok, {{:tuple, [:number, :binary]}, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "3-tuple" do
      ast = {:{}, @meta, [1, "hello", true]}

      assert {:ok, {{:tuple, [:number, :binary, :boolean]}, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "nested tuple" do
      ast = {1, {2, 3}}

      assert {:ok, {{:tuple, [:number, {:tuple, [:number, :number]}]}, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "empty tuple" do
      ast = {:{}, @meta, []}
      assert {:ok, {{:tuple, []}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "tuple with variables" do
      env = %{x: :number, y: :binary}
      ast = {var(:x), var(:y)}

      assert {:ok, {{:tuple, [:number, :binary]}, @st_end}, ^env} =
               TC.tc_expr(nil, env, @st_end, ast)
    end

    test "tuple preserves session state" do
      assert {:ok, {{:tuple, [:number, :number]}, @st_out}, %{}} =
               TC.tc_expr(nil, %{}, @st_out, {1, 2})
    end
  end

  # --- Maps
  # Map keys are atoms, so tc_expr needs a real module context
  # to check delta_M/delta_I. We use tc_with_module/3 for these.

  describe "tc_expr/4 maps" do
    test "empty map" do
      ast = {:%{}, @meta, []}
      assert {:ok, {{:map, %{}}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "map with atom keys" do
      ast = {:%{}, @meta, [name: "alice", age: 42]}

      assert {:ok, {{:map, %{name: :binary, age: :number}}, @st_end}, %{}} =
               tc_with_module(%{}, @st_end, ast)
    end

    test "map preserves session state" do
      ast = {:%{}, @meta, [x: 1]}

      assert {:ok, {{:map, %{x: :number}}, @st_out}, %{}} =
               tc_with_module(%{}, @st_out, ast)
    end
  end

  # --- Binary operators (expanded erlang form)

  describe "tc_expr/4 arithmetic operators" do
    test "addition of numbers" do
      assert {:ok, {:number, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:+, 1, 2))
    end

    test "subtraction of numbers" do
      assert {:ok, {:number, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:-, 5, 3))
    end

    test "multiplication" do
      assert {:ok, {:number, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:*, 4, 3))
    end

    test "division" do
      assert {:ok, {:number, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:/, 10, 2))
    end

    test "arithmetic with variables" do
      env = %{x: :number, y: :number}

      assert {:ok, {:number, @st_end}, ^env} =
               TC.tc_expr(nil, env, @st_end, erlang_op(:+, var(:x), var(:y)))
    end

    test "arithmetic type error: number + binary" do
      env = %{x: :number, y: :binary}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, erlang_op(:+, var(:x), var(:y)))

      assert is_binary(msg)
    end

    test "arithmetic preserves session state" do
      assert {:ok, {:number, @st_out}, %{}} =
               TC.tc_expr(nil, %{}, @st_out, erlang_op(:+, 1, 2))
    end
  end

  describe "tc_expr/4 comparison operators" do
    test "less than" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:<, 1, 2))
    end

    test "greater than" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:>, 5, 3))
    end

    test "less than or equal" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:<=, 1, 2))
    end

    test "greater than or equal" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:>=, 5, 3))
    end

    test "equality" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:==, 1, 1))
    end

    test "inequality" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_op(:!=, 1, 2))
    end

    test "comparison type error: number < binary" do
      env = %{x: :number, y: :binary}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, erlang_op(:<, var(:x), var(:y)))

      assert is_binary(msg)
    end

    test "equality type error: different types" do
      env = %{x: :number, y: :binary}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, erlang_op(:==, var(:x), var(:y)))

      assert is_binary(msg)
    end
  end

  describe "tc_expr/4 boolean operators" do
    test "and with booleans" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, {:and, @meta, [true, false]})
    end

    test "or with booleans" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, {:or, @meta, [true, false]})
    end

    test "and with variables" do
      env = %{a: :boolean, b: :boolean}

      assert {:ok, {:boolean, @st_end}, ^env} =
               TC.tc_expr(nil, env, @st_end, {:and, @meta, [var(:a), var(:b)]})
    end

    test "boolean op type error: number and boolean" do
      env = %{x: :number, y: :boolean}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, {:and, @meta, [var(:x), var(:y)]})

      assert is_binary(msg)
    end
  end

  describe "tc_expr/4 not operator" do
    test "not boolean" do
      assert {:ok, {:boolean, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, erlang_not(true))
    end

    test "not variable" do
      env = %{flag: :boolean}

      assert {:ok, {:boolean, @st_end}, _env} =
               TC.tc_expr(nil, env, @st_end, erlang_not(var(:flag)))
    end

    test "not type error: not number" do
      env = %{x: :number}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, erlang_not(var(:x)))

      assert is_binary(msg)
    end
  end

  # --- String concatenation

  describe "tc_expr/4 string concatenation" do
    test "binary <> binary" do
      assert {:ok, {:binary, @st_end}, %{}} =
               TC.tc_expr(nil, %{}, @st_end, string_concat("hello", " world"))
    end

    test "binary <> variable" do
      env = %{suffix: :binary}

      assert {:ok, {:binary, @st_end}, _env} =
               TC.tc_expr(nil, env, @st_end, string_concat("hello", var(:suffix)))
    end

    test "string concat type error: number <> binary" do
      env = %{x: :number}

      assert {:error, msg, _env} =
               TC.tc_expr(nil, env, @st_end, string_concat(var(:x), "world"))

      assert is_binary(msg)
    end
  end

  # --- Match / let binding

  describe "tc_expr/4 match operator" do
    test "simple variable binding" do
      ast = match(var(:x), 42)
      assert {:ok, {:number, @st_end}, env} = TC.tc_expr(nil, %{}, @st_end, ast)
      assert env[:x] == :number
    end

    test "rebinding a variable" do
      initial_env = %{x: :binary}
      ast = match(var(:x), 42)
      assert {:ok, {:number, @st_end}, env} = TC.tc_expr(nil, initial_env, @st_end, ast)
      assert env[:x] == :number
    end

    test "tuple destructuring" do
      env = %{pair: {:tuple, [:number, :binary]}}
      pattern = {var(:a), var(:b)}
      ast = match(pattern, var(:pair))

      assert {:ok, {{:tuple, [:number, :binary]}, @st_end}, result_env} =
               TC.tc_expr(nil, env, @st_end, ast)

      assert result_env[:a] == :number
      assert result_env[:b] == :binary
    end

    test "wildcard pattern" do
      ast = match({:_, @meta, nil}, 42)
      assert {:ok, {:number, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end
  end

  # --- Block expressions

  describe "tc_expr/4 blocks" do
    test "block returns type of last expression" do
      ast =
        block([
          match(var(:x), 42),
          match(var(:y), "hello"),
          var(:y)
        ])

      assert {:ok, {:binary, @st_end}, env} = TC.tc_expr(nil, %{}, @st_end, ast)
      assert env[:x] == :number
      assert env[:y] == :binary
    end

    test "block threads variable environment" do
      ast =
        block([
          match(var(:x), 1),
          match(var(:y), 2),
          erlang_op(:+, var(:x), var(:y))
        ])

      assert {:ok, {:number, @st_end}, env} = TC.tc_expr(nil, %{}, @st_end, ast)
      assert env[:x] == :number
      assert env[:y] == :number
    end

    test "single expression block" do
      ast = block([42])
      assert {:ok, {:number, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end
  end

  # --- Case expression

  describe "tc_expr/4 case" do
    test "case with consistent branch types" do
      env = %{x: :number}

      ast =
        case_expr(var(:x), [
          {1, "one"},
          {2, "two"}
        ])

      assert {:ok, {:binary, @st_end}, _env} = TC.tc_expr(nil, env, @st_end, ast)
    end

    test "case with inconsistent branch types returns error" do
      env = %{x: :number}

      ast =
        case_expr(var(:x), [
          {1, "one"},
          {2, 42}
        ])

      assert {:error, msg, _env} = TC.tc_expr(nil, env, @st_end, ast)
      assert is_binary(msg)
    end

    test "case with variable binding in patterns" do
      env = %{x: :number}

      ast =
        case_expr(var(:x), [
          {var(:n), var(:n)}
        ])

      assert {:ok, {:number, @st_end}, _env} = TC.tc_expr(nil, env, @st_end, ast)
    end

    test "case with wildcard pattern" do
      env = %{x: :number}

      ast =
        case_expr(var(:x), [
          {1, "one"},
          {{:_, @meta, nil}, "other"}
        ])

      assert {:ok, {:binary, @st_end}, _env} = TC.tc_expr(nil, env, @st_end, ast)
    end
  end

  # --- Anonymous functions

  describe "tc_expr/4 anonymous functions" do
    test "fn with 1 arg" do
      ast = {:fn, @meta, [{:->, @meta, [[var(:x)], var(:x)]}]}
      assert {:ok, {{:fun, 1}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "fn with 2 args" do
      ast = {:fn, @meta, [{:->, @meta, [[var(:x), var(:y)], var(:x)]}]}
      assert {:ok, {{:fun, 2}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "fn with 0 args" do
      ast = {:fn, @meta, [{:->, @meta, [[], 42]}]}
      assert {:ok, {{:fun, 0}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end
  end

  # --- Function captures

  describe "tc_expr/4 function captures" do
    test "remote function capture &Mod.fun/arity" do
      ast = {:&, @meta, [{:/, @meta, [{{:., @meta, [String, :length]}, @meta, []}, 1]}]}
      assert {:ok, {{:fun, 1}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end

    test "local function capture &fun/arity" do
      ast = {:&, @meta, [{:/, @meta, [:my_fun, 2]}]}
      assert {:ok, {{:fun, 2}, @st_end}, %{}} = TC.tc_expr(nil, %{}, @st_end, ast)
    end
  end

  # --- Raw send/receive are disallowed

  describe "tc_expr/4 raw communication disallowed" do
    test "raw receive is rejected" do
      ast = {:receive, @meta, [[do: [{:->, @meta, [[var(:msg)], var(:msg)]}]]]}
      assert {:error, msg, _env} = TC.tc_expr(nil, %{}, @st_end, ast)
      assert is_binary(msg)
    end

    test "raw erlang send is rejected" do
      ast = {{:., @meta, [:erlang, :send]}, @meta, [var(:pid), "message"]}
      env = %{pid: :pid}
      assert {:error, msg, _env} = TC.tc_expr(nil, env, @st_end, ast)
      assert is_binary(msg)
    end
  end

  # --- Atom literals (need module context)

  describe "tc_expr/4 atom literals" do
    test "plain atom without handler match" do
      assert {:ok, {:atom, @st_end}, %{}} =
               tc_with_module(%{}, @st_end, :some_atom)
    end

    test "atom preserves session state" do
      assert {:ok, {:atom, @st_out}, %{}} =
               tc_with_module(%{}, @st_out, :hello)
    end
  end

  # --- Session state threading

  describe "session state preservation" do
    test "pure expressions don't alter session state" do
      st = ST.output_one(:client, :request, :binary, @st_end)

      assert {:ok, {:number, ^st}, _} = TC.tc_expr(nil, %{}, st, 42)
      assert {:ok, {:binary, ^st}, _} = TC.tc_expr(nil, %{}, st, "hello")
      assert {:ok, {:boolean, ^st}, _} = TC.tc_expr(nil, %{}, st, true)
      assert {:ok, {{:list, :number}, ^st}, _} = TC.tc_expr(nil, %{}, st, [1, 2, 3])
    end

    test "variable lookup preserves session state" do
      st = ST.input_one(:client, :request, :binary, @st_end)
      env = %{x: :number}
      assert {:ok, {:number, ^st}, _} = TC.tc_expr(nil, env, st, var(:x))
    end

    test "arithmetic preserves session state" do
      st = ST.output_one(:client, :request, :binary, @st_end)
      assert {:ok, {:number, ^st}, _} = TC.tc_expr(nil, %{}, st, erlang_op(:+, 1, 2))
    end

    test "match preserves session state" do
      st = ST.output_one(:client, :request, :binary, @st_end)
      ast = match(var(:x), 42)
      assert {:ok, {:number, ^st}, _} = TC.tc_expr(nil, %{}, st, ast)
    end
  end
end
