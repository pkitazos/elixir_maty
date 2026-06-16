defmodule Maty.Typechecker.ErrorFormatterTest do
  use ExUnit.Case

  alias Maty.Typechecker.Error
  alias Maty.Typechecker.Error.Formatter
  alias Maty.Typechecker.TC.Bind

  @st_end %ST.SEnd{}
  @st_in ST.input_one(:buyer1, :title, :binary, @st_end)

  describe "format/1" do
    test "renders :incorrect_recipient_participant identically to the legacy builder" do
      built =
        Error.ProtocolViolation.incorrect_recipient_participant(
          TwoBuyer.Seller,
          :title_handler,
          @st_in,
          received: :buyer2,
          declared: :buyer1,
          expected: :buyer1
        )

      assert %Error{
               category: :protocol_violation,
               kind: :incorrect_recipient_participant,
               module: TwoBuyer.Seller,
               handler: :title_handler,
               st: @st_in,
               details: %{received: :buyer2, declared: :buyer1, expected: :buyer1}
             } = built

      expected =
        """
        \n\n** (ElixirMatyTypeError) Protocol Violation: Incorrect Incoming Participant
          Module: #{TwoBuyer.Seller}
          Handler: title_handler
          --
          Received role (handler arg): :buyer2
          Declared role (@spec): :buyer1
          Expected role (session type): :buyer1
          --
          Session Type: #{Maty.ST.repr(@st_in)}
        """

      assert Formatter.format(built) == expected
    end

    test "raises on an unknown {category, kind}" do
      error = %Error{category: :protocol_violation, kind: :does_not_exist}

      assert_raise ArgumentError, ~r/no Formatter clause/, fn ->
        Formatter.format(error)
      end
    end

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

  describe "Bind.with_frame/2" do
    test "prepends a frame onto a structured error (3-tuple shape)" do
      error = %Error{category: :protocol_violation, kind: :incorrect_recipient_participant}
      frame = {:call, {:foo, 2}, [line: 7]}

      assert {:error, %Error{trace: [^frame]}, %{}} =
               Bind.with_frame({:error, error, %{}}, frame)
    end

    test "prepends a frame onto a structured error (2-tuple shape)" do
      error = %Error{category: :protocol_violation, kind: :incorrect_recipient_participant}
      frame = {:clause, {:foo, 4}, 2}

      assert {:error, %Error{trace: [^frame]}} = Bind.with_frame({:error, error}, frame)
    end

    test "prepends frames innermost-first" do
      error = %Error{
        category: :protocol_violation,
        kind: :incorrect_recipient_participant,
        trace: [{:call, {:inner, 1}, []}]
      }

      outer = {:clause, {:outer, 4}, 1}

      assert {:error, %Error{trace: [^outer, {:call, {:inner, 1}, []}]}} =
               Bind.with_frame({:error, error}, outer)
    end

    test "passes string reasons through unchanged (migration passthrough)" do
      assert {:error, "boom", %{}} = Bind.with_frame({:error, "boom", %{}}, {:clause, {:f, 1}, 0})
      assert {:error, "boom"} = Bind.with_frame({:error, "boom"}, {:clause, {:f, 1}, 0})
    end

    test "passes successes through unchanged" do
      ok = Bind.ok(:number, %{}, @st_end)
      assert ^ok = Bind.with_frame(ok, {:clause, {:f, 1}, 0})
    end
  end
end
