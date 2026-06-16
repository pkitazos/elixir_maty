defmodule Maty.Typechecker do
  @moduledoc """
  This is the main public interface for Maty’s typechecking.

  - Called by `Maty.Hook` at compile-time
  - Delegates detailed checks to submodules
  """

  alias Maty.Utils
  alias Maty.Typechecker.{Ctx, Delta, TC, Error, Preprocessor}
  alias Maty.Typechecker.Error.Formatter

  require Logger

  @debug []

  @app Mix.Project.config()[:app]

  @doc """
  Called by Hook when a function definition is encountered (`@on_definition`).
  """
  def handle_on_definition(env, _kind, name, args, _guards, _body) do
    arity = length(args)

    session_types = Utils.Env.get_map(env.module, :st)
    handler = Module.get_attribute(env.module, :handler)

    if not is_nil(handler) do
      Preprocessor.process_handler_annotation(%{
        module: env.module,
        function: {name, arity},
        handler_label: handler,
        session_types: session_types,
        store: :delta_M,
        kind: :handler,
        meta: [line: env.line]
      })
    end

    init_handler = Module.get_attribute(env.module, :init_handler)

    if not is_nil(init_handler) do
      Preprocessor.process_handler_annotation(%{
        module: env.module,
        function: {name, arity},
        handler_label: init_handler,
        session_types: session_types,
        store: :delta_I,
        kind: :init_handler,
        meta: [line: env.line]
      })
    end

    Preprocessor.process_type_annotation(%{module: env.module, function: {name, args}})
  end

  @doc """
  Called by Hook at `@before_compile`.
  """
  def handle_before_compile(env) do
    # todo: potentially reverse the type_specs here

    Logger.debug(format_function_signatures(env.module))

    errors =
      Module.get_attribute(env.module, :spec_errors) ++
        Module.get_attribute(env.module, :handler_errors)

    if (err_count = length(errors)) > 0 do
      out = Enum.reduce(errors, "", fn err, acc -> acc <> inspect(err) <> "\n" end)

      Logger.error(out)
      throw({:phase_1, "#{err_count} errors you need to fix"})
    end
  end

  @doc """
  Called by Hook at `@after_compile`.
  """
  def handle_after_compile(env, bytecode) do
    # get the expanded AST of all the relevant definitions in this module from the bytecode
    # we omit the definitions injected into the scope by our behaviour as we can assume they are type-safe
    all_module_definitions = fetch_module_definitions!(bytecode)

    # Δ_M is the environment which maps message handler names to session type annotations
    delta_M = Module.get_attribute(env.module, :delta_M)

    # we get both, the list of tuples and the map, because I've not figured out what the cleanest thing is yet
    delta_m = Utils.Env.get_map(env.module, :delta_M)

    # similarly, Δ_I is the environment which maps init handler names to session type annotations
    delta_I = Module.get_attribute(env.module, :delta_I)
    # and again, I will eventually stick to only fetching one of the two
    delta_i = Utils.Env.get_map(env.module, :delta_I)

    # Ψ is the function definition environment, maps function names to type signatures
    psi = Utils.Env.get_map(env.module, :psi)

    # build the typing context struct for tc_expr and friends
    ctx = %Ctx{
      module: env.module,
      meta: [line: 0],
      delta_M: delta_m,
      delta_I: delta_i,
      psi: psi
    }

    # convert the lists of pairs into sets of fst for fast lookup (can also be optimised)
    module_init_handlers = Delta.key_set(delta_I)
    module_handlers = Delta.key_set(delta_M)

    # we then build up a list of errors
    # as things stand I have my errors just be big strings which I format in-place.
    # perhaps a better option would be to create structs and bubble those all the way up to here
    # and only format them once we reach this point
    errors =
      for {func_id, _kind, _meta, func_clauses} <- all_module_definitions, reduce: [] do
        # we reduce over the list of all the definitions in our module to accumulate errors
        acc ->
          cond do
            # if this particular function is a message handler
            # we check for its well-formedness
            MapSet.member?(module_handlers, func_id) ->
              {handler_name, 4} = func_id

              # we fetch the associated session type annotations for this handler
              handler_M = delta_m[handler_name]
              # and the associated type signatures
              type_signatures = psi[func_id] |> Enum.reverse()

              res =
                for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                  # because we may have multiple handler clauses, we need to iterate over
                  # all definitions and their associated type signatures and check if they are well-formed
                  TC.WF.check_wf_message_handler_clause(
                    ctx,
                    handler_name,
                    clause,
                    handler_M.st,
                    type_signature
                  )
                  |> case do
                    {:ok, %ST.SBranch{}} -> :ok
                    {:error, error_msg} -> error_msg
                  end
                end
                # then, for whatever reason I'm rejecting any branches that typechecked
                # ig if something typechecks there is nothing interesting to report
                |> Enum.reject(&(&1 == :ok))
                # and creating a list mapping the function id to whatever error it returned
                |> Enum.map(&{func_id, &1})

              # if we have more function clauses than branches, then we need to be a bit more vigilant about our session typechecking
              if(length(func_clauses) != length(handler_M.st.branches)) do
                # we need to explicitly keep track of all the visited branches
                # to ensure we sufficiently cover/support the annotated session type
                visited_branches =
                  for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                    # so as we iterate over the list of clauses and signatures we keep track of the branches we have visited
                    TC.WF.check_wf_message_handler_clause(
                      ctx,
                      handler_name,
                      clause,
                      handler_M.st,
                      type_signature
                    )
                    |> case do
                      # this means that after typechecking a clause, we record the session branch we went down
                      {:ok, %ST.SBranch{} = branch} -> branch
                      {:error, _msg} -> :error
                    end
                  end
                  # in this case what we're interested in  is not the individual errors,
                  # but whether or not we are actually sufficiently covering the session type
                  # so we can reject the errors
                  |> Enum.reject(&(&1 == :error))
                  # and we create a set containing the branches we covered
                  |> MapSet.new()

                # we check to see if we've covered all branches or not
                missing_branches =
                  handler_M.st.branches
                  |> MapSet.new()
                  |> MapSet.difference(visited_branches)
                  |> MapSet.to_list()

                # we format the missing branches into their string representation
                missing_st = Maty.ST.repr(%{handler_M.st | branches: missing_branches})

                # and report an error stating that we have violated the protocol definition
                error_msg =
                  Error.ProtocolViolation.incorrect_choice_implementation(
                    env.module,
                    handler_name,
                    missing_st,
                    handler_M.st
                  )

                # this error is cons-ed onto the accumulator
                [{func_id, error_msg} | acc]
              else
                # or otherwise the other result is appended
                res ++ acc
              end

            # the next thing we check is whether the function we're type-checking is the on_link callback
            func_id == {:on_link, 2} ->
              # in which case we can fetch its type spec definition to begin our typechecking
              type_signatures = psi[func_id] |> Enum.reverse()

              # here we unpack pattern match on our function clauses
              # to make sure we have only defined a single on_link function clause
              with {:clause, [clause]} <- {:clause, func_clauses},
                   {:signature, [type_signature]} <- {:signature, type_signatures} do
                TC.WF.check_wf_on_link_callback(
                  ctx,
                  clause,
                  type_signature
                )
                |> case do
                  :ok -> acc
                  # errors are propagated
                  {:error, error_msg} -> [{func_id, error_msg} | acc]
                end
              else
                {:clause, got} ->
                  error_msg =
                    Error.FunctionCall.wrong_number_of_clauses(env.module, func_id,
                      expected: 1,
                      got: length(got)
                    )

                  [{func_id, error_msg} | acc]

                {:signature, got} ->
                  error_msg =
                    Error.FunctionCall.wrong_number_of_specs(env.module, func_id,
                      expected: 1,
                      got: length(got)
                    )

                  [{func_id, error_msg} | acc]
              end

            # next we check to see if the function we're type-checking is an init_handler
            MapSet.member?(module_init_handlers, func_id) ->
              {handler_name, 3} = func_id

              # fetch the appropriate environments
              handler_I = delta_i[handler_name]
              type_signatures = psi[func_id] |> Enum.reverse()

              # and begin typechecking all clauses
              res =
                for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                  TC.WF.check_wf_init_handler_clause(
                    ctx,
                    handler_name,
                    clause,
                    handler_I.st,
                    type_signature
                  )
                  |> case do
                    :ok -> :ok
                    {:error, error_msg} -> error_msg
                  end
                end
                |> Enum.reject(&(&1 == :ok))
                |> Enum.map(&{func_id, &1})

              # propagating errors only
              res ++ acc

            # otherwise, this is just a regular function which we still need to check is well-formed
            true ->
              res =
                TC.WF.check_wf_function(ctx, func_id, func_clauses)
                |> Enum.reject(&match?({:ok, _}, &1))
                |> Enum.map(fn {:error, error_msg} -> {func_id, error_msg} end)

              res ++ acc
          end
      end

    # if we found any errors
    if length(errors) != 0 do
      for err <- errors do
        if Enum.member?(@debug, :verbose) do
          Logger.error("\n[#{env.module}] #{display_error(err)}")
        else
          {_, error_msg} = err
          # we log each error in its module
          Logger.error(normalise_error(error_msg), ansi_color: :light_red)
        end
      end
    else
      # otherwise we tell the user they are good to go
      Logger.info("\n[#{env.module}] No communication errors", ansi_color: :light_green)
    end
  end

  @typedoc "A top-level definition from debug_info: `{func_id, kind, meta, clauses}`."
  @type definition :: {{atom(), arity()}, atom(), keyword(), [tuple()]}

  @spec fetch_module_definitions!(binary()) :: [definition()]
  defp fetch_module_definitions!(bytecode) do
    bytecode
    |> read_debug_info!()
    |> Map.fetch!(:definitions)
    |> Enum.reject(fn {func_id, _, meta, _} ->
      Keyword.get(meta, :context) == Maty.Actor or match?({:__handler_expects__, _}, func_id)
    end)
  end

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

  # this could be moved elsewhere
  defp format_function_signatures(module) do
    module_header =
      "-------------------- #{inspect(module)} -------------------"

    display =
      module
      |> Module.get_attribute(:psi)
      |> Enum.map_join("\n\n", fn {k, v} -> "#{inspect(k)} --> \n#{inspect(v)}" end)

    "\n" <> module_header <> "\n" <> display <> "\n"
  end

  def display_error({func_id, error_msg}) do
    "[#{Utils.to_func(func_id)}] #{normalise_error(error_msg)}"
  end

  # During the migration to structured errors, results may carry either a
  # pre-formatted string (legacy) or an %Error{} struct.
  # Normalise both to the final report text here, will eventually kill this
  defp normalise_error(error_msg) when is_binary(error_msg), do: error_msg
  defp normalise_error(%Error{} = error), do: Formatter.format(error)
end
