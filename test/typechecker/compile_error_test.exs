defmodule Maty.Typechecker.CompileErrorTest do
  use ExUnit.Case

  defp compile_error!(src) do
    assert_raise CompileError, ~r/ElixirMatyTypeError/, fn ->
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
        use Maty.Actor

        @role :buyer1

        @st {:install, ~q/+seller:{title(binary).quote_handler}/}
        @st {:quote_handler, ~q/&seller:{quote(number).+buyer2:{share(number).end}}/}

        on_link {ap_pid, title} :: {pid(), binary()}, initial_state do
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [title]], initial_state)
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
        use Maty.Actor

        @role :buyer1

        @st {:install, ~q/+seller:{title(binary).end}/}

        on_link {ap_pid, title} :: {pid(), binary()}, initial_state do
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [title]], initial_state)
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
      [_, line] = Regex.run(~r/Line: (\d+)/, description)
      String.to_integer(line)
    end

    defp seller_src(module_name, body) do
      """
      defmodule MatyCompileErrorFixture.#{module_name} do
        use Maty.Actor

        @role :seller

        @st {:install, ~q/decision_handler/}
        @st {:decision_handler, ~q/&buyer2:{address(binary).+buyer2:{date(binary).end},quit(nil).end}/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [ap_pid]], initial_state)
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
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [ap_pid]], initial_state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Clauses"
      # the first on_link clause, not the line of the module
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
          use Maty.Actor

          @role :seller

          @st {:install, ~q/end/}

          def on_link(ap_pid, initial_state) do
            MatyDSL.register(ap_pid, @role, [callback: :install, args: [ap_pid]], initial_state)
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
      assert error.description =~ "Function: decision_handler/4"
    end

    test "a hand-written init handler without a spec reports the missing spec" do
      src = """
      defmodule MatyCompileErrorFixture.RawInitNoSpec do
        use Maty.Actor

        @role :seller

        @st {:install, ~q/end/}

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [ap_pid]], initial_state)
        end

        @init_handler :install
        def install(_session_ctx, _arg, state), do: MatyDSL.done(state)
      end
      """

      error = compile_error!(src)

      assert error.description =~ "Missing Function Spec"
      assert error.description =~ "Function: install/3"
    end
  end
end
