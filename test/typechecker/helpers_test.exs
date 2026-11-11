defmodule Maty.Typechecker.HelpersTest do
  use ExUnit.Case

  alias Maty.Typechecker.Helpers
  alias Maty.ST.SBottom

  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)

  # -- op_type_rel/3

  test "operator typing" do
    for op <- [:+, :-, :*, :/] do
      assert {:ok, :number} = Helpers.op_type_rel(op, :number, :number)
      assert :error = Helpers.op_type_rel(op, :number, :binary)
    end

    for op <- [:<, :>, :<=, :>=] do
      assert {:ok, :boolean} = Helpers.op_type_rel(op, :number, :number)
      assert :error = Helpers.op_type_rel(op, :binary, :number)
    end

    for op <- [:and, :or] do
      assert {:ok, :boolean} = Helpers.op_type_rel(op, :boolean, :boolean)
      assert :error = Helpers.op_type_rel(op, :number, :boolean)
    end

    for op <- [:==, :!=] do
      assert {:ok, :boolean} = Helpers.op_type_rel(op, :atom, :atom)
      assert :error = Helpers.op_type_rel(op, :number, :binary)
    end

    assert {:ok, :binary} = Helpers.op_type_rel(:<>, :binary, :binary)
    assert :error = Helpers.op_type_rel(:<>, :binary, :number)

    assert :error = Helpers.op_type_rel(:xor, :boolean, :boolean)
  end

  # -- join_branch_results/1

  test "joining branch results" do
    bottom = %SBottom{reason: :done}

    assert {:ok, {:no_return, %SBottom{reason: :nothing}}} = Helpers.join_branch_results([])
    assert {:ok, {:number, @st_end}} = Helpers.join_branch_results([{:number, @st_end}])

    assert {:ok, {:number, @st_end}} =
             Helpers.join_branch_results([{:no_return, bottom}, {:number, @st_end}])

    assert {:error, [t1: :number, t2: :binary]} =
             Helpers.join_branch_results([{:number, @st_end}, {:binary, @st_end}])

    assert {:error, [q1: @st_end, q2: @st_out]} =
             Helpers.join_branch_results([{:number, @st_end}, {:number, @st_out}])

    assert {:error, [t1: :number, t2: :binary, q1: @st_end, q2: @st_out]} =
             Helpers.join_branch_results([{:number, @st_end}, {:binary, @st_out}])
  end
end
