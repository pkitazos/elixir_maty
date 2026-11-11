defmodule Maty.Utils do
  require Logger
  # move
  # these are display functions for printing function ids
  # this should probably move, change and be renamed,
  # but it's good that it exists somewhere
  def to_func({name, arity}), do: "#{name}/#{arity}"
  # a function id that names its module, as Σ keys functions
  def to_func({module, name, arity}), do: "#{inspect(module)}.#{name}/#{arity}"
  def to_func(name: name, arity: arity), do: "#{name}/#{arity}"

  # this whole module needs some tlc
  # it's meant to make environment management simpler,
  # but right now it's just complicating things
  defmodule Env do
    def setup(module, attribute) do
      Module.register_attribute(module, attribute, accumulate: true, persist: true)
    end

    def get(module, attribute) do
      Module.get_attribute(module, attribute)
    end

    def get_map(module, attribute) do
      Module.get_attribute(module, attribute) |> Enum.into(%{})
    end

    def add_at_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, val, fn _ -> val end)
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    def prepend_to_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, [val], fn vals -> [val | vals] end)
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    def remove_from_key(module, attribute, key, val) do
      updated_entries =
        get_map(module, attribute)
        |> Map.update(key, [], &Enum.filter(&1, fn x -> x != val end))
        |> Map.to_list()

      rewrite(module, attribute, updated_entries)
    end

    defp rewrite(module, attribute, entries) do
      Module.delete_attribute(module, attribute)

      for entry <- entries do
        Module.put_attribute(module, attribute, entry)
      end
    end
  end

  if Application.compile_env(:maty, :debug_stack_trace, false) do
    defmacro stack_trace do
      quote do
        require Logger
        {func_name, func_arity} = __ENV__.function

        Logger.debug("[#{inspect(__MODULE__)}.#{func_name}/#{func_arity}:#{__ENV__.line}]")
      end
    end
  else
    defmacro stack_trace do
      :ok
    end
  end

  # Wrapper around `def` that injects a `stack_trace()` call at the top of each clause.
  # When MATY_DEBUG=1, logs the module, function, arity, and line number.
  # When debug is off, `stack_trace()` compiles to `:ok` and is optimized away.
  #
  # It also hands the clause's result to `ensure_run!/3` before returning it
  # For a clause written as
  #
  #     deftc synth(ctx, env, st, ast) do
  #       ...body...
  #     end
  #
  # the generated code is
  #
  #     def synth(ctx, env, st, ast) do
  #       Maty.Utils.stack_trace()
  #       result = ...body...
  #       Maty.Utils.ensure_run!(result, __MODULE__, __ENV__.function)
  #     end
  defmacro deftc(call, do: body) do
    quote do
      def unquote(call) do
        Maty.Utils.stack_trace()
        result = unquote(body)
        Maty.Utils.ensure_run!(result, __MODULE__, __ENV__.function)
      end
    end
  end

  # Catches a typechecking clause that returns a check it never ran.
  #
  # A `tcm do ... end` block does not typecheck anything by itself: it only *builds* a check,
  # which is a function `fn env, st -> result end` waiting to be given the starting env and
  # session type. Nothing happens until that function is called.
  # A `tcm env: env, st: st do ... end` block builds the check, and then runs it with `env` and `st`
  #
  # So a clause that uses `tcm do` at the top level, and forgets the `env:`/`st:`, (which has happened to me)
  # just returns that check function instead of a result.
  # Nothing would fail at that point: the function would travel up to wherever it was called from and only blow up there,
  # when it's matched against `{:ok, type, st, env}`, which gives a hard to reas error
  # (and also away from the clause that actually has the mistake)
  #
  # Every typechecking result is a tuple (`{:ok, ...}` or `{:error, ...}`), never a function, so
  # getting a 2-arity function back here can only mean an unrun check, and we stop right away
  # with an error that names the clause that forgot to run its check.
  @doc false
  def ensure_run!(check, module, {name, arity}) when is_function(check, 2) do
    raise ArgumentError,
          "#{inspect(module)}.#{name}/#{arity} returned a check that was never run. " <>
            "A `tcm do ... end` block only builds the check; run it from the clause's " <>
            "starting state with `tcm env: env, st: st do ... end`"
  end

  def ensure_run!(result, _module, _function), do: result
end
