defmodule Maty.Typechecker.CompileErrorTest do
  use ExUnit.Case

  defp compile_error!(src) do
    assert_raise CompileError, ~r/\[maty\]/, fn ->
      Code.with_diagnostics(fn -> Code.compile_string(src) end)
    end
  end

  # just literally copied over the contents of some of the examples and made some changes
  # that I know should cause our tool to throw a compile-time error

  describe "type errors fail compilation" do
    test "a protocol violation raises CompileError (after_compile path)" do
      # the :buyer1 actor, but the init handler sends `title` to :buyer2 when the session declares +seller
      src = """
      defmodule MatyCompileErrorFixture.BadTarget do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:buyer1]

        @role :buyer1

        @st {:install, ~q/+seller:{title(binary).quote_handler}/}
        @st {:quote_handler, ~q/&seller:{quote(number).+buyer2:{share(number).end}}/}

        on_link {ap_pid, title} :: {pid(), binary()}, initial_state do
          MatyDSL.register(ap_pid, @role, :install, title, initial_state)
        end

        init_handler :install, title :: binary(), state do
          MatyDSL.send(:buyer2, {:title, title})
          MatyDSL.suspend(:quote_handler, state)
        end

        handler :quote_handler, :seller, {:quote, amount :: number()}, state do
          share_amount = amount / 2
          MatyDSL.send(:buyer2, {:share, share_amount})
          MatyDSL.done(state)
        end
      end
      """

      compile_error!(src)
    end

    test "a missing handler label raises CompileError (before_compile path)" do
      # a handler annotated with a label that has no @st declaration.
      src = """
      defmodule MatyCompileErrorFixture.MissingHandler do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:buyer1]

        @role :buyer1

        @st {:install, ~q/+seller:{title(binary).end}/}

        on_link {ap_pid, title} :: {pid(), binary()}, initial_state do
          MatyDSL.register(ap_pid, @role, :install, title, initial_state)
        end

        handler :no_such_session_type, :seller, {:quote, amount :: number()}, state do
          MatyDSL.done(state)
        end
      end
      """

      compile_error!(src)
    end
  end

  describe "error context" do
    # the :seller actor with a two-branch session type

    # `clauses` spliced in as the handler definitions so each test can control what is wrong
    @valid_handlers """
    handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
      MatyDSL.send(:buyer2, {:date, addr})
      MatyDSL.done(state)
    end

    handler :decision_handler, :buyer2, {:quit, nil}, state do
      MatyDSL.done(state)
    end
    """

    # the 1-based line of the first line of `src` containing `needle`
    defp line_of(src, needle) do
      line =
        src
        |> String.split("\n")
        |> Enum.find_index(&String.contains?(&1, needle))

      line + 1
    end

    # the line the first error in the report says it is on
    defp own_line(%CompileError{description: description}) do
      [_, line] = Regex.run(~r/^[^\s:]+:(\d+): \[[^\]]+\/\d+\]/m, description)
      String.to_integer(line)
    end

    defp seller_src(module_name, body) do
      """
      defmodule MatyCompileErrorFixture.#{module_name} do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/decision_handler/}
        @st {:decision_handler, ~q/&buyer2:{address(binary).+buyer2:{date(binary).end},quit(nil).end}/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, :install, ap_pid, initial_state)
        end

        init_handler :install, _ap_pid :: pid(), state do
          MatyDSL.suspend(:decision_handler, state)
        end

        #{body}
      end
      """
    end

    test "per-clause errors are kept when the handler also misses a branch" do
      # one clause for a two-branch session type: the missing `quit` branch is reported,
      # and so is the error inside the clause that was provided
      src =
        seller_src("ClauseAndCoverage", """
        handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer1, {:date, addr})
          MatyDSL.done(state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Incomplete Message Handler Implementation"
      assert error.description =~ "Incorrect Target Participant"
    end

    test "an error in one clause of a multi-clause handler names that clause" do
      src =
        seller_src("HandlerClauseFrame", """
        handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer2, {:date, addr})
          MatyDSL.done(state)
        end

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.send(:buyer2, {:date, "never"})
          MatyDSL.done(state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "in clause #2 of decision_handler/4"
      refute error.description =~ "in clause #1"
    end

    test "an error in one clause of a multi-clause function names that clause" do
      src =
        seller_src("FunctionClauseFrame", """
        @spec f(number()) :: number()
        def f(1), do: 1

        @spec f(number()) :: number()
        def f(_x), do: "not a number"
        """)

      error = compile_error!(src)

      assert error.description =~ "Return Type Mismatch"
      assert error.description =~ "in clause #2 of f/1"
    end

    test "a single-clause function has no clause frame" do
      src =
        seller_src("SingleClause", """
        @spec f(number()) :: number()
        def f(_x), do: "not a number"
        """)

      error = compile_error!(src)

      assert error.description =~ "Return Type Mismatch"
      refute error.description =~ "Trace:"
    end

    test "the CompileError line is the definition line for errors built without one" do
      # on_link defined twice: wrong_number_of_clauses has no line of its own in the
      # source, it is taken from the function definition.
      # The handlers are valid so that this is the only error reported
      src =
        seller_src("OnLinkTwice", """
        #{@valid_handlers}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, :install, ap_pid, initial_state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "[maty] 1 type error in"
      assert error.description =~ "Wrong Number of Clauses"
      # the first on_link clause, not the line of the module
      assert own_line(error) == 9
      assert error.line == 9
    end

    test "a spec error is reported on its own, body errors wait until it is fixed" do
      # `g/0` has a body error that must not be reported yet
      src =
        seller_src("SpecErrorFirst", """
        #{@valid_handlers}

        @spec f(wat()) :: number()
        def f(_x), do: 1

        @spec g() :: number()
        def g(), do: "not a number"
        """)

      error = compile_error!(src)

      assert error.description =~ "Invalid Spec Argument"
      refute error.description =~ "Return Type Mismatch"
    end

    test "every error in the module is reported, each under its own function" do
      src =
        seller_src("MultipleErrors", """
        #{@valid_handlers}

        @spec f() :: number()
        def f(), do: "a"

        @spec g() :: number()
        def g(), do: "b"
        """)

      error = compile_error!(src)

      assert error.description =~ "[f/0]"
      assert error.description =~ "[g/0]"
      assert length(String.split(error.description, "Return Type Mismatch")) == 3
    end

    test "an error inside a call carries a call frame, and the CompileError line is its own line" do
      src =
        seller_src("CallFrame", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        def f(x), do: x

        @spec g() :: number()
        def g(), do: f(1 + "a")
        """)

      error = compile_error!(src)

      assert error.description =~ "Binary Operator"
      assert error.description =~ ~r/Trace:\n\s+via f\/1 \(line \d+\)/
      assert error.line == own_line(error)
      assert error.line == line_of(src, "def g(), do: f(1 + \"a\")")
    end

    test "an error in one clause of a multi-clause init handler names that clause" do
      # the init handler :install from seller_src is clause #1, this is clause #2
      src =
        seller_src("InitHandlerClauseFrame", """
        init_handler :install, _other :: binary(), state do
          MatyDSL.done(state)
        end

        #{@valid_handlers}
        """)

      error = compile_error!(src)

      assert error.description =~ "in clause #2 of install/3"
      refute error.description =~ "in clause #1"
    end

    test "a handler missing a branch is reported at the handler definition" do
      src =
        seller_src("MissingBranchLine", """
        handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer2, {:date, addr})
          MatyDSL.done(state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Incomplete Message Handler Implementation"
      assert error.line == line_of(src, "handler :decision_handler")
    end

    test "an on_link written without a spec reports the missing spec instead of crashing" do
      # the on_link macro always generates a spec, a hand-written def does not
      src =
        """
        defmodule MatyCompileErrorFixture.OnLinkNoSpec do
          use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

          @role :seller

          @st {:install, ~q/end/}

          def on_link(ap_pid, initial_state) do
            MatyDSL.register(ap_pid, @role, :install, ap_pid, initial_state)
          end

          init_handler :install, _ap_pid :: pid(), state do
            MatyDSL.done(state)
          end
        end
        """

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Specs"
      assert error.description =~ "Got specs: 0"
      assert error.line == line_of(src, "def on_link")
    end

    test "an error in a case branch names the branch and its line" do
      src =
        seller_src("CaseBranchFrame", """
        #{@valid_handlers}

        @spec g(number()) :: number()
        def g(x) do
          case x do
            1 -> 1
            _ -> 1 + "a"
          end
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Binary Operator"
      # the second branch, at the line of that branch rather than the line of the `case`
      assert error.description =~ "in case branch #2 (line #{line_of(src, "_ -> 1 + \"a\"")})"
      refute error.description =~ "in case branch #1"
    end

    test "an error in a nested case names both branches" do
      src =
        seller_src("NestedCaseBranchFrame", """
        #{@valid_handlers}

        @spec g(number()) :: number()
        def g(x) do
          case x do
            1 ->
              case x do
                2 -> 1 + "a"
                _ -> 3
              end

            _ ->
              2
          end
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "in case branch #1 (line #{line_of(src, "1 ->")})"
      assert error.description =~ "in case branch #1 (line #{line_of(src, "2 -> 1 + ")})"
    end

    test "a literal pattern mismatch in a function clause is reported at that clause, not line 0" do
      # a literal carries no meta of its own, so the error takes the line of its clause
      src =
        seller_src("LiteralPatternClause", """
        #{@valid_handlers}

        @spec f(binary()) :: number()
        def f(1), do: 1
        """)

      error = compile_error!(src)

      assert error.description =~ "Pattern Type Mismatch"
      assert own_line(error) == line_of(src, "def f(1)")
      assert error.line == line_of(src, "def f(1)")
    end

    test "a literal pattern mismatch in a case branch is reported at that branch" do
      src =
        seller_src("LiteralPatternBranch", """
        #{@valid_handlers}

        @spec g(number()) :: number()
        def g(x) do
          case x do
            1 -> 1
            "a" -> 2
          end
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Pattern Type Mismatch"
      assert own_line(error) == line_of(src, "\"a\" -> 2")
    end

    test "a hand-written message handler without a spec reports the missing spec" do
      src =
        seller_src("RawHandlerNoSpec", """
        @handler :decision_handler
        def decision_handler(_session_ctx, _role, {:quit, nil}, state), do: MatyDSL.done(state)
        """)

      error = compile_error!(src)

      assert error.description =~ "Missing Function Spec"

      assert error.description =~
               "[decision_handler/4] Type Specification Error: Missing Function Spec"
    end

    test "a hand-written init handler without a spec reports the missing spec" do
      src = """
      defmodule MatyCompileErrorFixture.RawInitNoSpec do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/end/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, :install, ap_pid, initial_state)
        end

        @init_handler :install
        def install(_session_ctx, _arg, state), do: MatyDSL.done(state)
      end
      """

      error = compile_error!(src)

      assert error.description =~ "Missing Function Spec"
      assert error.description =~ "[install/3] Type Specification Error: Missing Function Spec"
    end

    test "several specs on one clause are reported instead of one being silently dropped" do
      src =
        seller_src("OverloadedSpecs", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        @spec f(binary()) :: binary()
        def f(x), do: x
        """)

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Specs"
      assert error.description =~ "Expected specs: 1"
      assert error.description =~ "Got specs: 2"
      assert error.description =~ "[f/1]"
      # the line of one of the two specs
      assert error.line in [line_of(src, "@spec f(number())"), line_of(src, "@spec f(binary())")]
    end

    test "the trace lists frames innermost first" do
      # the failing branch is inside a case, which is itself an argument of the call to f/1
      src =
        seller_src("TraceOrder", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        def f(x), do: x

        @spec g(number()) :: number()
        def g(x) do
          f(
            case x do
              1 -> 1 + "a"
              _ -> 2
            end
          )
        end
        """)

      error = compile_error!(src)

      assert error.description =~ ~r/Trace:\n\s+in case branch #1 .*\n\s+via f\/1/
    end

    test "a wrongly typed argument to register is reported" do
      src =
        """
        defmodule MatyCompileErrorFixture.RegisterBadAp do
          use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

          @role :seller

          @st {:install, ~q/end/}

          on_link ap_pid :: pid(), initial_state do
            MatyDSL.register(:not_a_pid, @role, :install, ap_pid, initial_state)
          end

          init_handler :install, _ap_pid :: pid(), state do
            MatyDSL.done(state)
          end
        end
        """

      error = compile_error!(src)

      assert error.description =~ "Register Argument Type"
      assert error.description =~ "Argument: 1 (access point)"
      assert error.description =~ "Expected: :pid"
      assert error.line == line_of(src, "MatyDSL.register(:not_a_pid")
    end

    test "an on_link that never registers is reported at the on_link clause" do
      src = """
      defmodule MatyCompileErrorFixture.OnLinkNoRegister do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/end/}

        on_link _ap_pid :: pid(), initial_state do
          {:ok, initial_state}
        end

        init_handler :install, _ap_pid :: pid(), state do
          MatyDSL.done(state)
        end
      end
      """

      error = compile_error!(src)

      assert error.description =~ "Missing Session Registration"
      assert error.line == line_of(src, "on_link _ap_pid")
    end

    test "a handler whose role does not match the session type is reported at that clause" do
      # both branches are implemented, so this is the only error
      src =
        seller_src("WrongRole", """
        handler :decision_handler, :buyer1, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer2, {:date, addr})
          MatyDSL.done(state)
        end

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Incorrect Incoming Participant"
      assert error.line == line_of(src, "handler :decision_handler, :buyer1")
    end

    test "an init handler whose session type starts with a receive is reported at that clause" do
      src = """
      defmodule MatyCompileErrorFixture.InitStartsWithReceive do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/&buyer2:{quit(nil).end}/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, :install, ap_pid, initial_state)
        end

        init_handler :install, _ap_pid :: pid(), state do
          MatyDSL.done(state)
        end
      end
      """

      error = compile_error!(src)

      assert error.description =~ "Init Handler Starts With a Receive"
      assert error.line == line_of(src, "init_handler :install")
    end

    test "a function without a spec is reported at its first clause" do
      src =
        seller_src("NoSpec", """
        #{@valid_handlers}

        def h(x), do: x
        """)

      error = compile_error!(src)

      assert error.description =~ "Missing Function Spec"
      assert error.line == line_of(src, "def h(x)")
    end

    test "a failing clause still covers its branch, so no missing-branch error is added" do
      # three clauses for two branches, so coverage is checked. The address clause fails, but it
      # still implements the address branch. (the second quit clause can never match, which is
      # fine here, it only makes the clause count differ from the branch count)
      src =
        seller_src("FailingClauseCovers", """
        handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer1, {:date, addr})
          MatyDSL.done(state)
        end

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Incorrect Target Participant"
      refute error.description =~ "Incomplete Message Handler Implementation"
    end

    test "more clauses than branches compiles when every branch is covered" do
      src =
        seller_src("MoreClausesThanBranches", """
        #{@valid_handlers}

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end
        """)

      assert {[{MatyCompileErrorFixture.MoreClausesThanBranches, _}], _diagnostics} =
               Code.with_diagnostics(fn -> Code.compile_string(src) end)
    end

    test "one spec covers every clause, so a later clause is checked against it" do
      src =
        seller_src("OneSpecAllClauses", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        def f(1), do: 1
        def f(_x), do: "not a number"
        """)

      error = compile_error!(src)

      assert error.description =~ "Return Type Mismatch"
      assert error.description =~ "in clause #2 of f/1"
    end

    test "one spec per clause pairs each clause with its own spec, in source order" do
      src =
        seller_src("SpecPerClauseInOrder", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        def f(1), do: 1

        @spec f(binary()) :: binary()
        def f(_x), do: "a binary"
        """)

      assert {[{MatyCompileErrorFixture.SpecPerClauseInOrder, _}], _diagnostics} =
               Code.with_diagnostics(fn -> Code.compile_string(src) end)
    end

    test "a spec count that is neither one nor one per clause is reported" do
      src =
        seller_src("TooFewSpecs", """
        #{@valid_handlers}

        @spec f(number()) :: number()
        def f(1), do: 1

        @spec f(number()) :: number()
        def f(2), do: 2
        def f(_x), do: 3
        """)

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Specs"
      assert error.description =~ "Expected specs: 1 or 3"
      assert error.description =~ "Got specs: 2"
      assert error.line == line_of(src, "def f(1)")
    end

    test "a role that is not an atom is reported as register's second argument" do
      src =
        """
        defmodule MatyCompileErrorFixture.RegisterBadRole do
          use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

          @role :seller

          @st {:install, ~q/end/}

          on_link ap_pid :: pid(), initial_state do
            MatyDSL.register(ap_pid, "seller", :install, ap_pid, initial_state)
          end

          init_handler :install, _ap_pid :: pid(), state do
            MatyDSL.done(state)
          end
        end
        """

      error = compile_error!(src)

      assert error.description =~ "Argument: 2 (role)"
      assert error.description =~ "Expected: :atom"
      assert error.description =~ "Got: :binary"
    end

    test "a multi-clause function without a spec reports the missing spec once" do
      src =
        seller_src("NoSpecTwoClauses", """
        #{@valid_handlers}

        def h(1), do: 1
        def h(_x), do: 2
        """)

      error = compile_error!(src)

      assert length(String.split(error.description, "Missing Function Spec")) == 2
      refute error.description =~ "in clause"
    end

    test "spec errors and handler annotation errors are reported together" do
      src =
        seller_src("SpecAndAnnotationErrors", """
        #{@valid_handlers}

        handler :no_such_session_type, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end

        @spec f(wat()) :: number()
        def f(_x), do: 1
        """)

      error = compile_error!(src)

      assert error.description =~ "[maty] 2 type errors in"
      assert error.description =~ "Missing Handler"
      assert error.description =~ "Invalid Spec Argument"
    end

    test "errors are reported in source order, each at its own location" do
      # defined b, a, c: the report used to follow function names (a, b, c)
      src =
        seller_src("SourceOrder", """
        #{@valid_handlers}

        @spec b() :: number()
        def b(), do: "not a number"

        @spec a() :: number()
        def a(), do: "not a number"

        @spec c() :: number()
        def c(), do: "not a number"
        """)

      error = compile_error!(src)

      [b_line, a_line, c_line] = Enum.map(["def b()", "def a()", "def c()"], &line_of(src, &1))

      reported = Regex.scan(~r/^nofile:(\d+): \[(\w+\/\d)\]/m, error.description)

      assert Enum.map(reported, fn [_, line, func] -> {String.to_integer(line), func} end) ==
               [{b_line, "b/0"}, {a_line, "a/0"}, {c_line, "c/0"}]

      # the CompileError points at the first error in the file
      assert error.line == b_line
    end
  end

  describe "register" do
    # the :seller actor, registering with `register_call` from on_link
    # `init_handlers` replaces the default single-clause init handler taking a {pid, binary}
    defp register_src(module_name, register_call, init_handlers \\ nil) do
      init_handlers =
        init_handlers ||
          """
          init_handler :install, {_ap_pid, _title} :: {pid(), binary()}, state do
            MatyDSL.suspend(:decision_handler, state)
          end
          """

      """
      defmodule MatyCompileErrorFixture.#{module_name} do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/decision_handler/}
        @st {:decision_handler, ~q/&buyer2:{address(binary).+buyer2:{date(binary).end},quit(nil).end}/}

        on_link ap_pid :: pid(), initial_state do
          #{register_call}
        end

        #{init_handlers}

        #{@valid_handlers}
      end
      """
    end

    @two_clause_init_handler """
    init_handler :install, {_ap_pid, _title} :: {pid(), binary()}, state do
      MatyDSL.suspend(:decision_handler, state)
    end

    init_handler :install, {_ap_pid, _stock, _quantity} :: {pid(), number(), number()}, state do
      MatyDSL.suspend(:decision_handler, state)
    end
    """

    test "args of the wrong type are reported as register's fourth argument" do
      src =
        register_src(
          "RegisterBadArgs",
          "MatyDSL.register(ap_pid, @role, :install, {ap_pid, false}, initial_state)"
        )

      error = compile_error!(src)

      assert error.description =~ "Register Argument Type"
      assert error.description =~ "Argument: 4 (init handler args)"
      assert error.description =~ "Expected: {:tuple, [:pid, :binary]}\n"
      assert error.description =~ "Got: {:tuple, [:pid, :boolean]}"
      assert error.line == line_of(src, "MatyDSL.register(")
    end

    test "args are checked against every clause of a multi-clause init handler" do
      src =
        register_src(
          "RegisterBadArgsTwoClauses",
          "MatyDSL.register(ap_pid, @role, :install, 1, initial_state)",
          @two_clause_init_handler
        )

      error = compile_error!(src)

      assert error.description =~ "Argument: 4 (init handler args)"
      assert error.description =~ "Expected: one of: "
      assert error.description =~ "{:tuple, [:pid, :binary]}"
      assert error.description =~ "{:tuple, [:pid, :number, :number]}"
      assert error.description =~ "Got: :number"
    end

    test "args matching any clause of a multi-clause init handler are accepted" do
      src =
        register_src(
          "RegisterSecondClause",
          "MatyDSL.register(ap_pid, @role, :install, {ap_pid, 5, 10}, initial_state)",
          @two_clause_init_handler
        )

      assert [{MatyCompileErrorFixture.RegisterSecondClause, _}] = Code.compile_string(src)
    end

    test "an atom that is not an init handler is reported with the known init handlers" do
      src =
        register_src(
          "RegisterUnknownHandler",
          ~s|MatyDSL.register(ap_pid, @role, :nope, {ap_pid, "title"}, initial_state)|
        )

      error = compile_error!(src)

      assert error.description =~ "Unknown Init Handler"
      assert error.description =~ "Got: :nope"
      assert error.description =~ "Init handlers: :install"
      assert error.line == line_of(src, "MatyDSL.register(")
    end

    test "a message handler is not accepted as an init handler" do
      src =
        register_src(
          "RegisterMessageHandler",
          ~s|MatyDSL.register(ap_pid, @role, :decision_handler, {ap_pid, "title"}, initial_state)|
        )

      error = compile_error!(src)

      assert error.description =~ "Unknown Init Handler"
      assert error.description =~ "Got: :decision_handler"
    end

    test "an init handler that is not a literal atom is reported" do
      src =
        register_src("RegisterNonLiteralHandler", """
        handler_name = :install
        MatyDSL.register(ap_pid, @role, handler_name, {ap_pid, "title"}, initial_state)
        """)

      error = compile_error!(src)

      assert error.description =~ "Init Handler Not a Literal"
      assert error.description =~ "Got: handler_name"
      assert error.line == line_of(src, "MatyDSL.register(")
    end

    test "register with the wrong number of arguments is reported" do
      src =
        register_src(
          "RegisterWrongArity",
          "MatyDSL.register(ap_pid, @role, :install, initial_state)"
        )

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Arguments to register"
      assert error.description =~ "Got: 4"
      assert error.line == line_of(src, "MatyDSL.register(")
    end
  end

  describe "suspend" do
    # the :seller actor whose init handler suspends with `next_handler` the session type continues as `title_handler`
    defp suspend_src(module_name, next_handler) do
      """
      defmodule MatyCompileErrorFixture.#{module_name} do
        use Maty.Actor, protocol: TwoBuyer.Protocol, roles: [:seller]

        @role :seller

        @st {:install, ~q/title_handler/}
        @st {:title_handler, ~q/&buyer:{title(binary).end}/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, :install, nil, initial_state)
        end

        init_handler :install, nil, state do
          next_handler = :title_handler
          _ = next_handler
          MatyDSL.suspend(#{next_handler}, state)
        end

        handler :title_handler, :buyer, {:title, _title :: binary()}, state do
          MatyDSL.done(state)
        end
      end
      """
    end

    test "suspending with an init handler is reported" do
      src = suspend_src("SuspendInitHandler", ":install")

      error = compile_error!(src)

      assert error.description =~ "Suspended with Invalid Handler"
      assert error.description =~ "Tried: :install"
      assert error.line == line_of(src, "MatyDSL.suspend(")
    end

    test "suspending with a variable is reported" do
      src = suspend_src("SuspendVariable", "next_handler")

      error = compile_error!(src)

      assert error.description =~ "Suspended with Invalid Handler"
      assert error.description =~ "Tried: next_handler"
      assert error.line == line_of(src, "MatyDSL.suspend(")
    end

    test "suspending with the message handler the session type names compiles" do
      src = suspend_src("SuspendMessageHandler", ":title_handler")

      assert [{MatyCompileErrorFixture.SuspendMessageHandler, _}] = Code.compile_string(src)
    end
  end
end
