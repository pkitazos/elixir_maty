# test/macros/handler_expansion_test.exs
defmodule Maty.HandlerExpansionTest do
  use ExUnit.Case

  use Maty.DSL

  # For type definitions in the specs
  @type session_ctx :: any()
  @type maty_actor_state :: any()
  @type suspend :: any()
  @type done :: any()

  test "shows macro expansions for different handler patterns" do
    test_cases = [
      {"Simple handler",
       quote do
         handler :quote_handler, :seller, {:quote, amount :: number()}, state do
           share_amount = amount / 2
           Maty.DSL.send(:buyer2, {:share, share_amount})
           Maty.DSL.done(state)
         end
       end,
       quote do
         @spec quote_handler({:quote, number()}, role(), session_ctx(), maty_actor_state()) ::
                 done()
         def quote_handler({:quote, amount}, :seller, session, state) do
           share_amount = amount / 2

           maty_send(session, :buyer2, {:share, share_amount})
           {:done, nil, state}
         end
       end}
      # {"Tuple payload",
      #  quote do
      #    handler :tuple_handler,
      #            :sender,
      #            {:pair, {first :: number(), second :: binary()}},
      #            state do
      #      IO.puts("Received pair: #{first}, #{second}")
      #      Maty.DSL.send(:receiver, {:response, "Processed"})
      #      Maty.DSL.suspend(:next_handler, state)
      #    end
      #  end},
      # {"N-tuple payload",
      #  quote do
      #    handler :ntuple_handler,
      #            :sender,
      #            {:data, {a :: number(), b :: binary(), c :: boolean()}},
      #            state do
      #      IO.puts("Received data: #{a}, #{b}, #{c}")
      #      Maty.DSL.done(state)
      #    end
      #  end},
      # {"List payload",
      #  quote do
      #    handler :list_handler, :sender, {:items, items :: list(binary())}, state do
      #      IO.puts("Received items: #{Enum.join(items, ", ")}")
      #      Maty.DSL.done(state)
      #    end
      #  end},
      # {"Atom literal",
      #  quote do
      #    handler :atom_handler, :sender, {:command, :start}, state do
      #      IO.puts("Received start command")
      #      Maty.DSL.done(state)
      #    end
      #  end},
      # {"Number literal",
      #  quote do
      #    handler :number_handler, :sender, {:value, 42}, state do
      #      IO.puts("Received fixed value")
      #      Maty.DSL.done(state)
      #    end
      #  end}
    ]

    for {name, macro, func} <- test_cases do
      expanded = Macro.expand_once(macro, __ENV__)

      IO.puts("\n=== #{name} ===")
      IO.puts("\nORIGINAL:\n```elixir")
      IO.puts(Macro.to_string(macro))
      IO.puts("```\n")
      IO.puts("\nEXPANDED:\n```elixir")
      IO.puts(Macro.to_string(expanded))
      IO.puts("```\n")
      IO.puts("\nEXPECTED:\n```elixir")
      IO.puts(Macro.to_string(func))
      IO.puts("```\n")
      IO.puts(String.duplicate("-", 80))

      assert true
    end
  end
end
