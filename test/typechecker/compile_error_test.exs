defmodule Maty.Typechecker.CompileErrorTest do
  use ExUnit.Case

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

      assert_raise CompileError, ~r/ElixirMatyTypeError/, fn ->
        Code.compile_string(src)
      end
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

      assert_raise CompileError, ~r/ElixirMatyTypeError/, fn ->
        Code.compile_string(src)
      end
    end
  end
end
