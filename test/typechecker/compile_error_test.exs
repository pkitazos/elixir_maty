defmodule Maty.Typechecker.CompileErrorTest do
  use ExUnit.Case

  # a small actor (:seller from `TwoBuyer.Protocol`) for use in tests
  # opts can replace default parts, so tests only need to write the code they care about

  @st """
  session_type :seller, %{
    install: ~q/decision_handler/,
    decision_handler: ~q/&buyer2:{address(binary).+buyer2:{date(binary).end},quit(nil).end}/
  }
  """

  @on_start "Maty.DSL.register(ap_pid, :seller, &install/2, ap_pid)"

  @init """
  defhandler install(_ap_pid :: pid(), state) do
    Maty.DSL.suspend(&decision_handler/3, state)
  end
  """

  @handlers """
  defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
    Maty.DSL.send_to(:buyer2, {:date, addr})
    Maty.DSL.done(state)
  end

  defhandler decision_handler(:buyer2, {:quit, nil}, state) do
    Maty.DSL.done(state)
  end
  """

  defp actor_src(body, opts \\ []) do
    roles = Keyword.get(opts, :roles, [:seller])
    local_states = Enum.map_join(roles, "\n", &"local_state #{inspect(&1)}, nil")

    """
    defmodule MatyCompileErrorFixture.M#{System.unique_integer([:positive])} do
    use Maty.Actor, protocol: TwoBuyer.Protocol

    global_state nil
    #{local_states}

    #{Keyword.get(opts, :st, @st)}

    on_start ap_pid :: pid() do
    #{Keyword.get(opts, :on_start, @on_start)}
    nil
    end

    #{Keyword.get(opts, :init, @init)}

    #{Keyword.get(opts, :handlers, @handlers)}

    #{body}
    end
    """
  end

  defp compile_error!(src) do
    assert_raise CompileError, ~r/\[maty\]/, fn ->
      Code.with_diagnostics(fn -> Code.compile_string(src) end)
    end
  end

  defp compiles!(src) do
    assert {[{_module, _bytecode}], _diagnostics} =
             Code.with_diagnostics(fn -> Code.compile_string(src) end)
  end

  # the 1-based line of the first line of `src` containing `needle`
  defp line_of(src, needle) do
    index = src |> String.split("\n") |> Enum.find_index(&String.contains?(&1, needle))
    index + 1
  end

  # -- How errors are reported

  test "before_compile errors are reported together and hold back body checks" do
    # `g/0` has a body error, which is not reported until the errors above it are fixed
    src =
      actor_src("""
      defhandler no_such_session_type(:buyer2, {:quit, nil}, state) do
        Maty.DSL.done(state)
      end

      @spec f(wat()) :: number()
      def f(_x), do: 1

      @spec g() :: number()
      def g(), do: "not a number"
      """)

    error = compile_error!(src)

    assert error.description =~ "[maty] 2 type errors in"
    assert error.description =~ "Missing Handler"
    assert error.description =~ "Invalid Spec Argument"
    refute error.description =~ "Unexpected Type"
  end

  test "every error in the module is reported, in source order" do
    src =
      actor_src("""
      @spec b() :: number()
      def b(), do: "not a number"

      @spec a() :: number()
      def a(), do: "not a number"
      """)

    error = compile_error!(src)

    assert error.description =~ "[maty] 2 type errors in"
    {b, _} = :binary.match(error.description, "[b/0]")
    {a, _} = :binary.match(error.description, "[a/0]")
    assert b < a
  end

  test "clause frames" do
    # an error in one clause of a multi-clause definition names that clause
    handler =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer2, {:date, addr})
          Maty.DSL.done(state)
        end

        defhandler decision_handler(:buyer2, {:quit, nil}, state) do
          Maty.DSL.send_to(:buyer2, {:date, "never"})
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(handler)
    assert error.description =~ "in clause #2 of decision_handler/4"
    refute error.description =~ "in clause #1"

    init =
      actor_src("",
        init: """
        #{@init}

        defhandler install(_other :: pid(), state) do
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(init)
    assert error.description =~ "in clause #2 of install/3"
    refute error.description =~ "in clause #1"

    function =
      actor_src("""
      @spec f(number()) :: number()
      def f(1), do: 1
      def f(_x), do: "not a number"
      """)

    error = compile_error!(function)
    assert error.description =~ "Unexpected Type"
    assert error.description =~ "in clause #2 of f/1"

    # a single-clause function needs no clause frame
    single =
      actor_src("""
      @spec f(number()) :: number()
      def f(_x), do: "not a number"
      """)

    error = compile_error!(single)
    assert error.description =~ "Unexpected Type"
    refute error.description =~ "Trace:"
  end

  test "trace frames" do
    # the failing expression is in a case, in a case, in an argument of a call to f/1:
    # the trace lists the frames innermost first
    nested =
      actor_src("""
      @spec f(number()) :: number()
      def f(x), do: x

      @spec g(number()) :: number()
      def g(x) do
        f(
          case x do
            1 ->
              case x do
                2 -> 1 + "a"
                _ -> 3
              end

            _ ->
              2
          end
        )
      end
      """)

    error = compile_error!(nested)

    assert error.description =~
             ~r/Trace:\n\s+in case branch #1 .*\n\s+in case branch #1 .*\n\s+in argument #1\n\s+via f\/1/

    # only the branch the error is in is named
    second_branch =
      actor_src("""
      @spec g(number()) :: number()
      def g(x) do
        case x do
          1 -> 1
          _ -> 1 + "a"
        end
      end
      """)

    error = compile_error!(second_branch)
    assert error.description =~ "in case branch #2"
    refute error.description =~ "in case branch #1"
  end

  test "errors point at their expression's line" do
    src =
      actor_src("""
      @spec f(number()) :: number()
      def f(x), do: x

      @spec g() :: number()
      def g() do
        f(1 + "a")
      end
      """)

    error = compile_error!(src)
    assert error.line == line_of(src, ~s|f(1 + "a")|)
  end

  test "errors with no line of their own point at their definition" do
    # a literal pattern carries no meta, so the error takes the line of its clause
    src =
      actor_src("""
      @spec f(binary()) :: number()
      def f(1), do: 1
      """)

    error = compile_error!(src)
    assert error.description =~ "Pattern Type Mismatch"
    assert error.line == line_of(src, "def f(1)")
  end

  # -- Handlers against their session types

  test "message handler branch coverage" do
    # a missing branch is reported alongside the errors in the clauses that are there
    missing =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer1, {:date, addr})
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(missing)
    assert error.description =~ "Incomplete Message Handler Implementation"
    assert error.description =~ "Incorrect Target Participant"

    # as many clauses as branches, but both handle :address and none handles :quit
    duplicate =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer2, {:date, addr})
          Maty.DSL.done(state)
        end

        defhandler decision_handler(:buyer2, {:address, other :: binary()}, state) do
          Maty.DSL.send_to(:buyer2, {:date, other})
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(duplicate)
    assert error.description =~ "Incomplete Message Handler Implementation"

    # a clause that fails still covers the branch it handles
    failing =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer1, {:date, addr})
          Maty.DSL.done(state)
        end

        defhandler decision_handler(:buyer2, {:quit, nil}, state) do
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(failing)
    assert error.description =~ "Incorrect Target Participant"
    refute error.description =~ "Incomplete Message Handler Implementation"

    # more clauses than branches is fine as long as every branch is covered
    compiles!(
      actor_src("",
        handlers: """
        #{@handlers}

        defhandler decision_handler(:buyer2, {:quit, nil}, state) do
          Maty.DSL.done(state)
        end
        """
      )
    )
  end

  test "a message handler whose session type is not a receive is reported once" do
    src =
      actor_src("",
        st: """
        session_type :seller, %{
          install: ~q/decision_handler/,
          decision_handler: ~q/+buyer2:{date(binary).end}/
        }
        """
      )

    error = compile_error!(src)
    assert error.description =~ "[maty] 1 type error in"
    assert error.description =~ "Message Handler Does Not Receive"
  end

  test "handler heads against their session types" do
    wrong_role =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer1, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer2, {:date, addr})
          Maty.DSL.done(state)
        end

        defhandler decision_handler(:buyer2, {:quit, nil}, state) do
          Maty.DSL.done(state)
        end
        """
      )

    assert compile_error!(wrong_role).description =~ "Incorrect Incoming Participant"

    # the label picks the branch, so a wrong payload on the second label is a payload error,
    # not an unknown label
    wrong_payload =
      actor_src("",
        handlers: """
        defhandler decision_handler(:buyer2, {:address, addr :: binary()}, state) do
          Maty.DSL.send_to(:buyer2, {:date, addr})
          Maty.DSL.done(state)
        end

        defhandler decision_handler(:buyer2, {:quit, 5}, state) do
          Maty.DSL.done(state)
        end
        """
      )

    error = compile_error!(wrong_payload)
    assert error.description =~ "Pattern Type Mismatch"
    refute error.description =~ "Incorrect Incoming Message Label"

    init_receives =
      actor_src("",
        st: "session_type :seller, %{install: ~q/&buyer2:{quit(nil).end}/}",
        init: """
        defhandler install(_ap_pid :: pid(), state) do
          Maty.DSL.done(state)
        end
        """,
        handlers: ""
      )

    assert compile_error!(init_receives).description =~ "Init Handler Starts With a Receive"
  end

  # todo: fails until a handler's payload annotation is checked against its session type
  # (`defhandler` strips `:: number()` from the pattern, and the bare variable matches any type)
  test "a payload annotation that disagrees with the session type is reported" do
    src =
      actor_src("",
        handlers: """
        #{@handlers}

        defhandler decision_handler(:buyer2, {:quit, _n :: number()}, state) do
          Maty.DSL.done(state)
        end
        """
      )

    compile_error!(src)
  end

  test "sending a wrong payload on the second label reports the payload" do
    src =
      actor_src("",
        st: "session_type :seller, %{install: ~q/+buyer2:{date(binary).end,quit(nil).end}/}",
        init: """
        defhandler install(ap_pid :: pid(), state) do
          Maty.DSL.send_to(:buyer2, {:quit, ap_pid})
          Maty.DSL.done(state)
        end
        """,
        handlers: ""
      )

    error = compile_error!(src)
    assert error.description =~ "in the payload of message `:quit`"
    refute error.description =~ "Incorrect Message Label"
  end

  # -- Function specs

  test "function specs" do
    # a function without a spec is reported once, not once per clause
    no_spec =
      actor_src("""
      def h(1), do: 1
      def h(_x), do: 2
      """)

    error = compile_error!(no_spec)
    assert length(String.split(error.description, "Missing Function Spec")) == 2
    refute error.description =~ "in clause"

    # a function takes exactly one spec, whether the specs are on one clause or spread over several
    for body <- [
          """
          @spec f(number()) :: number()
          @spec f(binary()) :: binary()
          def f(x), do: x
          """,
          """
          @spec f(number()) :: number()
          def f(1), do: 1

          @spec f(binary()) :: binary()
          def f(_x), do: "a binary"
          """
        ] do
      error = compile_error!(actor_src(body))
      assert error.description =~ "Wrong Number of Specs"
      assert error.description =~ "Expected specs: 1"
      assert error.description =~ "Got specs: 2"
    end
  end

  test "a spec can use the module's own types" do
    # `order` uses `book`, which is declared after it
    compiles!(
      actor_src("""
      @type order :: {book(), number()}
      @typep book :: %{title: binary(), price: number()}

      @spec price(book()) :: order()
      def price(b), do: {b, 1}
      """)
    )
  end

  test "recursive, parametric and remote module types are reported" do
    error =
      compile_error!(
        actor_src("""
        @type a :: list(b())
        @type b :: {a(), number()}
        @type p(x) :: list(x)
        @type r :: String.t()
        """)
      )

    assert error.description =~ "Invalid Module Type"
    assert error.description =~ "Recursive Type"
    assert error.description =~ "Parametric Type"
    assert error.description =~ "Remote Type"
  end

  # -- on_start, register and suspend

  test "roles" do
    not_literal =
      actor_src("", on_start: ~s|Maty.DSL.register(ap_pid, "seller", &install/2, ap_pid)|)

    error = compile_error!(not_literal)
    assert error.description =~ "Role Not a Literal"
    assert error.description =~ ~s(Got: "seller")

    wrong_role =
      actor_src("", on_start: "Maty.DSL.register(ap_pid, :buyer1, &install/2, ap_pid)")

    error = compile_error!(wrong_role)
    assert error.description =~ "Init Handler Role Mismatch"
    assert error.description =~ "Got: :buyer1"

    not_in_protocol =
      actor_src("", roles: [:seller, :auditor], st: @st <> "session_type :auditor, %{}")

    error = compile_error!(not_in_protocol)
    assert error.description =~ "Unknown Roles"
    assert error.description =~ "Got: :auditor"
  end

  test "register arguments" do
    bad_ap =
      actor_src("", on_start: "Maty.DSL.register(:not_a_pid, :seller, &install/2, ap_pid)")

    error = compile_error!(bad_ap)
    assert error.description =~ "Expected: :pid"
    assert error.description =~ "in the access point"

    bad_args =
      actor_src("", on_start: ~s|Maty.DSL.register(ap_pid, :seller, &install/2, "not a pid")|)

    error = compile_error!(bad_args)
    assert error.description =~ "in the init handler's argument"
    assert error.description =~ "Expected: :pid"
    assert error.description =~ "Got: :binary"

    never_registers = actor_src("", on_start: "")
    assert compile_error!(never_registers).description =~ "Missing Session Registration"
  end

  test "register's handler argument" do
    function =
      actor_src(
        """
        @spec nope(pid()) :: atom()
        def nope(_ap_pid), do: :ok
        """,
        on_start: "Maty.DSL.register(ap_pid, :seller, &nope/1, ap_pid)"
      )

    assert compile_error!(function).description =~ "Expected an Init Handler"

    remote =
      actor_src("", on_start: "Maty.DSL.register(ap_pid, :seller, &Kernel.elem/2, ap_pid)")

    assert compile_error!(remote).description =~ "Function Does Not Exist"

    message_handler =
      actor_src("", on_start: "Maty.DSL.register(ap_pid, :seller, &decision_handler/3, ap_pid)")

    error = compile_error!(message_handler)
    assert error.description =~ "Expected an Init Handler"
    assert error.description =~ "Got: message handler"

    variable =
      actor_src("",
        on_start: """
        handler = :install
        Maty.DSL.register(ap_pid, :seller, handler, ap_pid)
        """
      )

    error = compile_error!(variable)
    assert error.description =~ "Expected an Init Handler"
    assert error.description =~ "Got: :atom"
  end

  test "init handler clauses must take the same argument type" do
    src =
      actor_src("",
        init: """
        #{@init}

        defhandler install(_n :: number(), state) do
          Maty.DSL.suspend(&decision_handler/3, state)
        end
        """
      )

    assert compile_error!(src).description =~ "Init Handler Clauses Take Different Types"
  end

  test "suspend's handler argument" do
    init_handler =
      actor_src("",
        init: """
        defhandler install(_ap_pid :: pid(), state) do
          Maty.DSL.suspend(&install/2, state)
        end
        """
      )

    error = compile_error!(init_handler)
    assert error.description =~ "Expected a Message Handler"
    assert error.description =~ "Got: init handler"

    variable =
      actor_src("",
        init: """
        defhandler install(_ap_pid :: pid(), state) do
          next = :decision_handler
          Maty.DSL.suspend(next, state)
        end
        """
      )

    error = compile_error!(variable)
    assert error.description =~ "Expected a Message Handler"
    assert error.description =~ "Got: :atom"

    # a message handler, but not the one the session type continues as
    other_handler =
      actor_src("",
        st: """
        session_type :seller, %{
          install: ~q/decision_handler/,
          decision_handler: ~q/&buyer2:{address(binary).+buyer2:{date(binary).end},quit(nil).end}/,
          other_handler: ~q/&buyer2:{quit(nil).end}/
        }
        """,
        init: """
        defhandler install(_ap_pid :: pid(), state) do
          Maty.DSL.suspend(&other_handler/3, state)
        end
        """,
        handlers: """
        #{@handlers}

        defhandler other_handler(:buyer2, {:quit, nil}, state) do
          Maty.DSL.done(state)
        end
        """
      )

    assert compile_error!(other_handler).description =~ "Handler for a Different Session Type"

    # the default actor suspends with the handler its session type continues as
    compiles!(actor_src(""))
  end

  # -- Expressions that expansion rewrites
  # (the forms that look the same before and after expansion are tested in `tc_expr_test.exs`)

  # `code` as the body of a function with one argument of each type it needs
  defp function_src(code) do
    actor_src("""
    @spec f(number(), binary(), boolean(), pid()) :: number()
    def f(n, s, b, p) do
      #{code}
    end
    """)
  end

  test "operators and strings that compile" do
    src =
      actor_src(~S"""
      @spec arith(number(), number()) :: number()
      def arith(x, y), do: -(x + y * x - y / x)

      @spec compare(number(), number()) :: boolean()
      def compare(x, y), do: x < y and x <= y and x >= y and x > y and x == y and x != y

      # `a and b` keeps a `:badbool` branch after expansion, `x > 1 and b` does not
      @spec bools(boolean(), boolean(), number()) :: boolean()
      def bools(a, b, x), do: not ((a and b) or a) or (x > 1 and b)

      @spec strings(binary(), number()) :: binary()
      def strings(s, n), do: "#{s} has #{n} " <> s
      """)

    compiles!(src)
  end

  test "operator and string type errors" do
    for {code, title} <- [
          {~S|n + s|, "Binary Operator Type Error"},
          # `<=` expands to `:erlang.=<`, but is reported as written
          {~S|n <= s|, "Operator: <="},
          {~S|b and n|, "Logical Operator Type Error"},
          {~S|b && b|, "Unsupported Operator"},
          {~S|-s|, "Arithmetic Operator Type Error"},
          {~S|not n|, "Logical Operator Type Error"},
          {~S|n <> s|, "String Concatenation"},
          {~S|"#{p}"|, "String Interpolation"},
          {~S|<<n::8>>|, "Unsupported Bitstring"}
        ] do
      error = compile_error!(function_src(code))
      assert error.description =~ title, "#{code} should report #{title}"
    end
  end

  test "rejected expressions" do
    for {code, title} <- [
          {~S|String.length(s)|, "Unsupported Expression"},
          {~S|send(p, n)|, "Attempted Native Communication"},
          {~S"""
           case n do
             x when x > 0 -> x
             _ -> 0
           end
           """, "Unsupported Pattern"}
        ] do
      error = compile_error!(function_src(code))
      assert error.description =~ title, "#{code} should report #{title}"
    end
  end
end
