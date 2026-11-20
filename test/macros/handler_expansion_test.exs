defmodule Maty.HandlerExpansionTest.Handlers do
  use Maty.DSL

  defhandler done_handler(:seller, {:quote, amount}, state) do
    Maty.DSL.done({amount, state})
  end

  defhandler suspend_handler(:worker, {:task, data}, state) do
    Maty.DSL.suspend(&done_handler/3, {data, state})
  end
end

defmodule Maty.HandlerExpansionTest do
  use ExUnit.Case

  alias Maty.HandlerExpansionTest.Handlers

  # what a handler returns and what `__handler_expects__` reports is what `Maty.Runtime` relies on

  test "done and suspend return their results" do
    assert {:done, {100, :state}} = Handlers.done_handler(:seller, {:quote, 100}, :state, nil)

    assert {:suspend, :done_handler, {"data", :state}} =
             Handlers.suspend_handler(:worker, {:task, "data"}, :state, nil)
  end

  test "__handler_expects__ maps each handler to its role" do
    assert :seller == Handlers.__handler_expects__(:done_handler)
    assert :worker == Handlers.__handler_expects__(:suspend_handler)
  end
end
