defmodule Maty.Typechecker.ErrorFormatterTest do
  use ExUnit.Case

  alias Maty.Typechecker.Error
  alias Maty.Typechecker.Error.Formatter

  @st_end %ST.SEnd{}
  @st_in ST.input_one(:buyer1, :title, :binary, @st_end)

  describe "format/1" do
    test "appends trace frames after the error body" do
      error = %Error{
        category: :protocol_violation,
        kind: :incorrect_recipient_participant,
        module: TwoBuyer.Seller,
        handler: :title_handler,
        st: @st_in,
        details: %{received: :buyer2, declared: :buyer1, expected: :buyer1},
        trace: [
          {:call, {:process_title, 2}, [line: 40]},
          {:clause, {:title_handler, 4}, 1}
        ]
      }

      rendered = Formatter.format(error)

      assert rendered =~ "  Trace:\n"
      assert rendered =~ "    via process_title/2 (line 40)\n"
      assert rendered =~ "    in clause #1 of title_handler/4"
      assert rendered =~ ~r/Session Type: .*\n  Trace:/s
    end
  end
end
