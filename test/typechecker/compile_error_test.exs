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
    # `clauses` is spliced in as the handler (and function) definitions so that each test controls what is wrong
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
        handler :decision_handler, :buyer2, {:address, addr :: binary()}, state do
          MatyDSL.send(:buyer2, {:date, addr})
          MatyDSL.done(state)
        end

        handler :decision_handler, :buyer2, {:quit, nil}, state do
          MatyDSL.done(state)
        end

        on_link ap_pid :: pid(), initial_state do
          MatyDSL.register(ap_pid, @role, [callback: :install, args: [ap_pid]], initial_state)
        end
        """)

      error = compile_error!(src)

      assert error.description =~ "Wrong Number of Clauses"
      # the first on_link clause, not the line of the module
      assert error.line == 9
    end
  end
end
