defmodule Maty.Typechecker.TCBindTest do
  use ExUnit.Case

  alias Maty.Typechecker.TC.Bind

  @st_end %ST.SEnd{}
  @st_out ST.output_one(:server, :msg, :binary, @st_end)
  @env %{x: :number, y: :binary}

  describe "ok/3" do
    test "wraps value with st and env" do
      assert {:ok, :number, @st_end, @env} = Bind.ok(:number, @env, @st_end)
    end
  end

  describe "error/2" do
    test "wraps reason with env" do
      assert {:error, "bad type", @env} = Bind.error("bad type", @env)
    end
  end

  describe "bind/2" do
    test "success calls continuation with unpacked value, env, st" do
      result = Bind.ok(:number, @env, @st_end)

      assert {:ok, :transformed, @st_end, @env} =
               Bind.bind(result, fn :number, env, st ->
                 Bind.ok(:transformed, env, st)
               end)
    end

    test "error 3-tuple short-circuits" do
      result = Bind.error("fail", @env)

      assert {:error, "fail", @env} =
               Bind.bind(result, fn _, _, _ -> raise "should not be called" end)
    end

    test "chains two successful binds" do
      Bind.ok(1, %{}, @st_end)
      |> Bind.bind(fn val, env, st -> Bind.ok(val + 10, Map.put(env, :a, :atom), st) end)
      |> Bind.bind(fn val, env, st -> Bind.ok(val * 2, env, st) end)
      |> then(fn result ->
        assert {:ok, 22, @st_end, %{a: :atom}} = result
      end)
    end
  end

  describe "map/2" do
    test "transforms value on success" do
      result = Bind.ok(5, @env, @st_end)
      assert {:ok, 10, @st_end, @env} = Bind.map(result, &(&1 * 2))
    end

    test "short-circuits on error" do
      result = Bind.error("fail", @env)
      assert {:error, "fail", @env} = Bind.map(result, &(&1 * 2))
    end
  end

  describe "traverse/4" do
    test "empty list returns empty list" do
      assert {:ok, [], @st_end, @env} =
               Bind.traverse([], @env, @st_end, fn _, _, _ -> raise "not called" end)
    end

    test "all items succeed, values collected in order" do
      assert {:ok, [10, 20, 30], @st_end, @env} =
               Bind.traverse([1, 2, 3], @env, @st_end, fn item, env, st ->
                 Bind.ok(item * 10, env, st)
               end)
    end

    test "first error halts traversal" do
      assert {:error, "boom", _env} =
               Bind.traverse([1, 2, 3], @env, @st_end, fn
                 2, env, _st -> Bind.error("boom", env)
                 item, env, st -> Bind.ok(item, env, st)
               end)
    end

    test "threads env through items" do
      assert {:ok, [:a, :b, :c], @st_end, %{a: 1, b: 2, c: 3}} =
               Bind.traverse([:a, :b, :c], %{}, @st_end, fn item, env, st ->
                 index = map_size(env) + 1
                 Bind.ok(item, Map.put(env, item, index), st)
               end)
    end

    test "threads st through items" do
      assert {:ok, _, @st_out, @env} =
               Bind.traverse([1], @env, @st_end, fn _item, env, _st ->
                 Bind.ok(:done, env, @st_out)
               end)
    end
  end

  describe "fan_out/4" do
    test "all succeed, returns {value, st} pairs" do
      assert {:ok, [{10, @st_end}, {20, @st_end}], @st_end, @env} =
               Bind.fan_out([1, 2], @env, @st_end, fn item, env, st ->
                 Bind.ok(item * 10, env, st)
               end)
    end

    test "one failure returns error with original env" do
      assert {:error, "boom", @env} =
               Bind.fan_out([1, 2, 3], @env, @st_end, fn
                 2, env, _st -> Bind.error("boom", env)
                 item, env, st -> Bind.ok(item, env, st)
               end)
    end

    test "all items see the same original env and st" do
      assert {:ok, values, @st_end, %{}} =
               Bind.fan_out([:a, :b], %{}, @st_end, fn item, env, st ->
                 Bind.ok({item, env}, env, st)
               end)

      assert [{{:a, %{}}, _}, {{:b, %{}}, _}] = values
    end
  end

  describe "lift_result/4" do
    test "ok tuple lifts value" do
      assert {:ok, 42, @st_end, @env} = Bind.lift_result({:ok, 42}, "unused", @env, @st_end)
    end

    test "error tuple replaces reason" do
      assert {:error, "replaced", @env} =
               Bind.lift_result({:error, "original"}, "replaced", @env, @st_end)
    end

    test "bare :error replaces with given error" do
      assert {:error, "replaced", @env} = Bind.lift_result(:error, "replaced", @env, @st_end)
    end
  end

  describe "lift_result/3" do
    test "ok tuple lifts value" do
      assert {:ok, 42, @st_end, @env} = Bind.lift_result({:ok, 42}, @env, @st_end)
    end

    test "error tuple preserves original reason" do
      assert {:error, "kept", @env} = Bind.lift_result({:error, "kept"}, @env, @st_end)
    end
  end

  describe "lift_bool/4" do
    test "true lifts to ok with nil value" do
      assert {:ok, nil, @st_end, @env} = Bind.lift_bool(true, "unused", @env, @st_end)
    end

    test "false lifts to error" do
      assert {:error, "nope", @env} = Bind.lift_bool(false, "nope", @env, @st_end)
    end
  end
end
