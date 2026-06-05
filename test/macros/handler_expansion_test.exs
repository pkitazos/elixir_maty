defmodule Maty.HandlerExpansionTest.Handlers do
  use Maty.DSL

  @type session_ctx :: any()
  @type maty_actor_state :: any()

  # Simple annotated variable
  handler :simple_handler, :seller, {:quote, amount :: number()}, state do
    Maty.DSL.done({:received, amount, state})
  end

  # 2-tuple payload
  handler :tuple_handler, :sender, {:pair, {first :: number(), second :: binary()}}, state do
    Maty.DSL.done({first, second, state})
  end

  # 3-tuple payload
  handler :ntuple_handler,
          :sender,
          {:data, {a :: number(), b :: binary(), c :: boolean()}},
          state do
    Maty.DSL.done({a, b, c, state})
  end

  # List payload
  handler :list_handler, :sender, {:items, items :: list(binary())}, state do
    Maty.DSL.done({items, state})
  end

  # Atom literal payload
  handler :atom_handler, :sender, {:command, :start}, state do
    Maty.DSL.done({:started, state})
  end

  # Number literal payload
  handler :number_handler, :sender, {:value, 42}, state do
    Maty.DSL.done({:matched, state})
  end

  # Suspend instead of done
  handler :suspend_handler, :worker, {:task, data :: binary()}, state do
    Maty.DSL.suspend(:next_handler, {data, state})
  end
end

defmodule Maty.HandlerExpansionTest do
  use ExUnit.Case

  use Maty.DSL

  @type session_ctx :: any()
  @type maty_actor_state :: any()

  alias Maty.HandlerExpansionTest.Handlers

  # --- Runtime: simple annotated variable payload ---

  describe "simple annotated variable payload" do
    test "binds variable and returns done" do
      assert {:done, {:received, 100, %{}}} =
               Handlers.simple_handler(:seller, {:quote, 100}, %{}, nil)
    end

    test "passes through state unchanged" do
      assert {:done, {:received, 50, :my_state}} =
               Handlers.simple_handler(:seller, {:quote, 50}, :my_state, nil)
    end
  end

  # --- Runtime: tuple payloads ---

  describe "2-tuple payload" do
    test "destructures both elements" do
      assert {:done, {42, "hello", %{}}} =
               Handlers.tuple_handler(:sender, {:pair, {42, "hello"}}, %{}, nil)
    end
  end

  describe "3-tuple payload" do
    test "destructures all three elements" do
      assert {:done, {1, "two", true, %{}}} =
               Handlers.ntuple_handler(:sender, {:data, {1, "two", true}}, %{}, nil)
    end
  end

  # --- Runtime: list payload ---

  describe "list payload" do
    test "binds list variable" do
      assert {:done, {["a", "b", "c"], %{}}} =
               Handlers.list_handler(:sender, {:items, ["a", "b", "c"]}, %{}, nil)
    end

    test "works with empty list" do
      assert {:done, {[], %{}}} =
               Handlers.list_handler(:sender, {:items, []}, %{}, nil)
    end
  end

  # --- Runtime: literal payloads ---

  describe "atom literal payload" do
    test "matches exact atom" do
      assert {:done, {:started, %{}}} =
               Handlers.atom_handler(:sender, {:command, :start}, %{}, nil)
    end

    test "rejects non-matching atom" do
      assert_raise FunctionClauseError, fn ->
        Handlers.atom_handler(:sender, {:command, :stop}, %{}, nil)
      end
    end
  end

  describe "number literal payload" do
    test "matches exact number" do
      assert {:done, {:matched, %{}}} =
               Handlers.number_handler(:sender, {:value, 42}, %{}, nil)
    end

    test "rejects non-matching number" do
      assert_raise FunctionClauseError, fn ->
        Handlers.number_handler(:sender, {:value, 99}, %{}, nil)
      end
    end
  end

  # --- Runtime: suspend ---

  describe "suspend" do
    test "returns suspend tuple with next handler and new state" do
      assert {:suspend, :next_handler, {"task_data", %{}}} =
               Handlers.suspend_handler(:worker, {:task, "task_data"}, %{}, nil)
    end
  end

  # --- Runtime: role matching ---

  describe "role matching" do
    test "wrong role raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Handlers.simple_handler(:buyer, {:quote, 100}, %{}, nil)
      end
    end
  end

  # --- Expansion structure ---

  describe "expansion structure" do
    test "generates __handler_expects__ mapping role to handler" do
      assert :seller == Handlers.__handler_expects__(:simple_handler)
      assert :sender == Handlers.__handler_expects__(:tuple_handler)
      assert :sender == Handlers.__handler_expects__(:ntuple_handler)
      assert :sender == Handlers.__handler_expects__(:list_handler)
      assert :sender == Handlers.__handler_expects__(:atom_handler)
      assert :sender == Handlers.__handler_expects__(:number_handler)
      assert :worker == Handlers.__handler_expects__(:suspend_handler)
    end

    test "all handlers are exported with arity 4" do
      for name <- [
            :simple_handler,
            :tuple_handler,
            :ntuple_handler,
            :list_handler,
            :atom_handler,
            :number_handler,
            :suspend_handler
          ] do
        assert function_exported?(Handlers, name, 4),
               "expected #{name}/4 to be exported"
      end
    end

    test "expansion produces def, spec, and __handler_expects__" do
      ast =
        quote do
          handler(:my_handler, :role_a, {:msg, data :: binary()}, state) do
            Maty.DSL.done(state)
          end
        end

      expanded = Macro.expand_once(ast, __ENV__)
      code = Macro.to_string(expanded)

      assert code =~ "my_handler"
      assert code =~ "__handler_expects__"
      assert code =~ "@spec"
    end
  end
end
