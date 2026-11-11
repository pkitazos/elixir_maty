defmodule Maty.Typechecker do
  @moduledoc """
  This is the main public interface for Maty’s typechecking.

  - Called by `Maty.Hook` at compile-time
  - Delegates detailed checks to submodules
  """

  alias Maty.Utils
  alias Maty.Typechecker.{Ctx, Delta, TC, Error, Preprocessor, Signatures}
  alias Maty.Typechecker.Error.Formatter

  require Logger

  @app Mix.Project.config()[:app]

  @debug Application.compile_env(:maty, :debug_function_signatures, false)

  @doc """
  Called by Hook when a function definition is encountered (`@on_definition`).
  """
  def handle_on_definition(env, _kind, name, args, _guards, _body) do
    arity = length(args)

    clause =
      Signatures.clause(name, arity, env.line, %{
        handler: Module.get_attribute(env.module, :handler),
        init_handler: Module.get_attribute(env.module, :init_handler),
        handler_stub: Module.get_attribute(env.module, :handler_stub),
        spec: Module.get_attribute(env.module, :spec)
      })

    Module.put_attribute(env.module, :maty_clauses, clause)

    # the annotations belong to this clause only, so they must not be seen by the next one
    for annotation <- [:handler, :init_handler, :handler_stub, :spec] do
      Module.delete_attribute(env.module, annotation)
    end
  end

  @doc """
  Called by Hook at `@before_compile`.
  """
  def handle_before_compile(env) do
    # todo: potentially reverse the type_specs here

    customise_logger()

    if @debug do
      Logger.debug(format_function_signatures(env.module))
    end

    {state_types, state_errors} =
      case Preprocessor.process_state_declarations(env) do
        {:ok, state_types} -> {state_types, []}
        # state errors carry no function id, so they are tagged with nil to match the other error sources.
        {:error, errors} -> {nil, Enum.map(errors, &{nil, &1})}
      end

    errors =
      Module.get_attribute(env.module, :handler_errors) ++
        unknown_role_errors(env) ++
        state_errors

    # we fail here, before the bodies are checked in `handle_after_compile`, on purpose:
    # a spec or handler annotation that did not validate leaves psi and delta incomplete,
    # so checking bodies against them would only pile follow-on errors on top of the real one
    if errors != [] do
      raise_type_errors!(env, errors)
    end

    Module.put_attribute(env.module, :state_types, state_types)

    # Σ is built next to the old environments for now
    # the checks above stay the ones that report, so an error here is one only `Signatures` finds
    clauses = Module.get_attribute(env.module, :maty_clauses) |> Enum.reverse()
    session_types = Utils.Env.get_map(env.module, :st)

    case Signatures.build(env.module, clauses, session_types) do
      {:ok, signatures} -> Module.put_attribute(env.module, :maty_signatures, signatures)
      {:error, errors} -> raise_type_errors!(env, errors)
    end
  end

  # every role an actor declares in `use Maty.Actor` must be a role of its protocol
  @spec unknown_role_errors(Macro.Env.t()) :: [{nil, Error.t()}]
  defp unknown_role_errors(env) do
    protocol = Module.get_attribute(env.module, :maty_protocol)
    roles = Module.get_attribute(env.module, :maty_roles)

    protocol_roles = protocol.__roles__()

    case Enum.uniq(roles -- protocol_roles) do
      [] ->
        []

      unknown_roles ->
        error =
          Error.FrameworkUsage.unknown_roles(
            env.module,
            [line: env.line],
            protocol,
            unknown_roles,
            protocol_roles
          )

        [{nil, error}]
    end
  end

  @doc """
  Called by Hook at `@after_compile`.
  """
  def handle_after_compile(env, bytecode) do
    # get the expanded AST of all the relevant definitions in this module from the bytecode
    # we omit the definitions injected into the scope by our behaviour as we can assume they are type-safe
    all_module_definitions = fetch_module_definitions!(env.module, bytecode)

    # build the typing context struct for synth and friends
    ctx = %Ctx{
      module: env.module,
      # until a clause sets its own, errors that have no location of their own point at the module
      meta: [line: env.line],
      roles: Module.get_attribute(env.module, :maty_roles),
      signatures: Module.get_attribute(env.module, :maty_signatures)
    }

    # we then build up a list of `{func_id, %Error{}}` pairs
    # the errors are structs which bubble all the way up to here
    # and are only formatted once we report them in `raise_type_errors!`
    errors =
      for {{name, _arity} = func_id, _kind, meta, cs} <- all_module_definitions,
          reduce: [] do
        # we reduce over the list of all the definitions in our module to accumulate errors
        acc ->
          ctx = %{ctx | meta: meta}

          errs =
            cond do
              match?({:handler, :message, _}, ctx.signatures[name]) ->
                deal_with_message_handler(ctx, name, cs)

              # next we check to see if the function we're type-checking is an init_handler
              match?({:handler, :init, _, _}, ctx.signatures[name]) ->
                deal_with_init_handler(ctx, name, cs)

              # the next thing we check is whether the function we're type-checking is the on_link callback
              func_id == {:on_start, 1} ->
                deal_with_on_start(ctx, func_id, cs)

              # otherwise, this is just a regular function which we still need to check is well-formed
              true ->
                deal_with_function(ctx, func_id, cs)
            end

          errs ++ acc
      end

    if errors != [] do
      # if we found any errors, fail compilation
      raise_type_errors!(env, errors)
    else
      # todo: sort these messages
      # modules compile in parallel so needs collecting the results after compilation
      # (e.g. a compiler tracer or a mix compiler step) since each module is checked in its own after_compile hook
      # (maybe more trouble than it's worth)
      Logger.info("\n[#{env.module}] No communication errors", ansi_color: :light_green)
    end
  end

  defp deal_with_message_handler(ctx, handler, cs) do
    {:handler, :message, st} = ctx.signatures[handler]
    check_message_handler(ctx, handler, cs, st)
  end

  defp check_message_handler(ctx, handler, cs, %ST.SIn{} = st) do
    func_id = {handler, 4}

    # because we may have multiple handler clauses, we need to iterate over
    # all definitions and their associated type signatures and check if they are well-formed
    # we typecheck each clause exactly once, and derive both the per-clause errors
    # and the visited session branches from these results
    errs =
      collect_clauses_errs(
        func_id,
        cs,
        &TC.WF.check_wf_message_handler_clause(ctx, handler, &1, st)
      )

    # we need to explicitly keep track of all the visited branches
    # to ensure we sufficiently cover/support the annotated session type
    # and we create a set containing the branches we covered
    visited_labels = MapSet.new(cs, &extract_label/1)

    # we check to see if we've covered all branches or not
    missing_branches = Enum.reject(st.branches, &MapSet.member?(visited_labels, &1.label))

    if missing_branches == [] do
      errs
    else
      e =
        Error.ProtocolViolation.incorrect_choice_implementation(
          ctx.module,
          ctx.meta,
          handler,
          missing_branches,
          st
        )

      [{func_id, e} | errs]
    end
  end

  defp check_message_handler(ctx, handler, _cs, st) do
    error = Error.ProtocolViolation.message_handler_not_receive(ctx.module, ctx.meta, handler, st)
    [{{handler, 4}, error}]
  end

  defp deal_with_init_handler(ctx, handler, cs) do
    {:handler, :init, args_ty, st} = ctx.signatures[handler]

    collect_clauses_errs(
      {handler, 3},
      cs,
      &TC.WF.check_wf_init_handler_clause(ctx, handler, &1, st, args_ty)
    )
  end

  # ? does it even make sense to extract this out?
  defp collect_clauses_errs(func_id, cs, f) do
    for {c, i} <- Enum.with_index(cs, 1),
        {:error, e} <- [with_clause_frame(f.(c), func_id, i, length(cs))],
        do: {func_id, e}
  end

  defp extract_label(clause) do
    {_meta, [_role, {label, _payload}, _state, _session_ctx], _guards, _block} = clause
    label
  end

  defp deal_with_on_start(ctx, {name, arity} = func_id, cs) do
    # here we unpack pattern match on our function clauses
    # to make sure we have only defined a single on_link function clause
    with {:clause, [clause]} <- {:clause, cs},
         # Σ keys functions by their module too, and has no entry for one without a spec
         {:spec, {:ok, ty}} <- {:spec, Map.fetch(ctx.signatures, {ctx.module, name, arity})},
         :ok <- TC.WF.check_wf_on_start_callback(ctx, clause, ty) do
      []
    else
      {:spec, :error} ->
        # reported at the clause since the spec belongs to the function as a whole
        {first_clause_meta, _, _, _} = hd(cs)

        err =
          Error.TypeSpecification.no_spec_for_function(
            ctx.module,
            first_clause_meta,
            {ctx.module, name, arity}
          )

        [{func_id, err}]

      {:clause, got} ->
        err =
          Error.FunctionCall.wrong_number_of_clauses(ctx.module, ctx.meta, func_id,
            expected: 1,
            got: length(got)
          )

        [{func_id, err}]

      {:error, err} ->
        [{func_id, err}]
    end
  end

  defp deal_with_function(ctx, func_id, cs) do
    case TC.WF.check_wf_function(ctx, func_id, cs) do
      # a problem with the function as a whole, reported once and without a clause frame
      {:error, error} ->
        [{func_id, error}]

      rs ->
        collect_clauses_errs(
          func_id,
          rs,
          & &1
        )
    end
  end

  @typedoc "A top-level definition from debug_info: `{func_id, kind, meta, clauses}`."
  @type definition :: {{atom(), arity()}, atom(), keyword(), [tuple()]}

  @spec fetch_module_definitions!(module(), binary()) :: [definition()]
  defp fetch_module_definitions!(module, bytecode) do
    stub_defs =
      for %{kind: :handler_stub} = c <- Module.get_attribute(module, :maty_clauses),
          do: {c.name, c.arity}

    bytecode
    |> read_debug_info!()
    |> Map.fetch!(:definitions)
    |> Enum.reject(fn {func_id, _, meta, _} ->
      Keyword.get(meta, :context) == Maty.Actor or
        match?({:__handler_expects__, _}, func_id) or
        Enum.member?(stub_defs, func_id)
    end)
  end

  # -- below this line does not spark joy

  # Function to read debug information from bytecode.
  #
  # Adapted from: https://github.com/gertab/ElixirST by Gerard Tabone
  # License: GPL-3.0 license
  @spec read_debug_info!(binary()) :: map()
  defp read_debug_info!(bytecode) do
    with {:ok, {_mod, chunks}} <- :beam_lib.chunks(bytecode, [:debug_info]),
         {:debug_info_v1, :elixir_erl, metadata} <- chunks[:debug_info],
         {:metadata, {:elixir_v1, map, _}} <- {:metadata, metadata} do
      map
    else
      {:error, _, reason} ->
        raise "[#{@app}] could not read :debug_info from bytecode: #{inspect(reason)}"

      {:metadata, {version, _, _}} ->
        raise "[#{@app}] got unexpected debug_info version #{inspect(version)}, expected :elixir_v1"

      other ->
        raise "[#{@app}] got unexpected debug_info shape: #{inspect(other)}"
    end
  end

  # because the Logger handler is installed when the VM actually boots up
  # (i.e. before our :logger config is applied)
  # I can't atually configure the compile-time logs via the config like normal
  # apparently you can configure the handler's formatter directly
  # by dropping down Erlang's :logger module
  defp customise_logger do
    :logger.update_handler_config(
      :default,
      :formatter,
      # strip timestamps from compile-time logs
      Logger.Formatter.new(format: "[$level] $message\n")
    )
  end

  # LSP thinks this is never used cause it obv compiles without the env vars
  @compile {:nowarn_unused_function, format_function_signatures: 1}
  defp format_function_signatures(module) do
    module_header =
      "-------------------- #{inspect(module)} -------------------"

    display =
      module
      |> Module.get_attribute(:psi)
      |> Enum.map_join("\n\n", fn {k, v} -> "#{inspect(k)} --> \n#{inspect(v)}" end)

    "\n" <> module_header <> "\n" <> display <> "\n"
  end

  # tags a clause's error with the clause it came from, so errors from different clauses
  # of the same function can be identified. single-clause functions needs no such context
  defp with_clause_frame({:error, %Error{} = e}, func_id, index, total_clauses)
       when total_clauses > 1,
       do: {:error, %{e | trace: e.trace ++ [{:clause, func_id, index}]}}

  defp with_clause_frame(result, _func_id, _index, _total_clauses), do: result

  def display_error(location, {nil, error_msg}) do
    "#{location}: #{Formatter.format(error_msg)}"
  end

  def display_error(location, {func_id, error_msg}) do
    "#{location}: [#{Utils.to_func(func_id)}] #{Formatter.format(error_msg)}"
  end

  @spec raise_type_errors!(Macro.Env.t(), [{term(), Error.t()}]) :: no_return()
  defp raise_type_errors!(env, errors) do
    count = length(errors)

    header =
      "[#{@app}] #{count} type #{if count == 1, do: "error", else: "errors"} in #{inspect(env.module)}"

    # errors are reported in the order they appear in the source, each with its own file:line,
    # and the CompileError points at the first one
    file = Path.relative_to_cwd(env.file)

    located =
      errors
      |> Enum.map(fn {_func_id, error} = entry -> {error_line_or(error, env.line), entry} end)
      |> Enum.sort_by(fn {line, {_func_id, error}} -> {line, error.meta[:column] || 0} end)

    description =
      header <>
        "\n\n" <>
        Enum.map_join(located, "\n", fn {line, entry} ->
          display_error("#{file}:#{line}", entry)
        end)

    [{line, _entry} | _] = located

    raise CompileError, file: env.file, line: line, description: description
  end

  # errors that carry no line of their own fall back to the line of the module being compiled
  defp error_line_or(%Error{meta: meta}, fallback), do: meta[:line] || fallback
end
