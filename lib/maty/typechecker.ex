defmodule Maty.Typechecker do
  @moduledoc """
  This is the main public interface for Maty’s typechecking.

  - Called by `Maty.Hook` at compile-time
  - Delegates detailed checks to submodules
  """

  alias Maty.Utils
  alias Maty.Typechecker.Delta
  alias Maty.Typechecker.TC
  alias Maty.Typechecker.Error
  alias Maty.Typechecker.Preprocessor

  require Logger

  @debug []

  @doc """
  Called by Hook when a function definition is encountered (`@on_definition`).
  """
  def handle_on_definition(env, _kind, name, args, _guards, _body) do
    arity = length(args)

    session_types = Maty.Utils.Env.get_map(env.module, :st)
    handler = Module.get_attribute(env.module, :handler)

    if not is_nil(handler) do
      Preprocessor.process_handler_annotation(
        module: env.module,
        function: {name, arity},
        handler_label: handler,
        session_types: session_types,
        store: :delta_M,
        kind: :handler,
        meta: [line: env.line]
      )
    end

    init_handler = Module.get_attribute(env.module, :init_handler)

    if not is_nil(init_handler) do
      Preprocessor.process_handler_annotation(
        module: env.module,
        function: {name, arity},
        handler_label: init_handler,
        session_types: session_types,
        store: :delta_I,
        kind: :init_handler,
        meta: [line: env.line]
      )
    end

    Preprocessor.process_type_annotation(module: env.module, function: {name, args})
  end

  @doc """
  Called by Hook at `@before_compile`.
  """
  def handle_before_compile(env) do
    # todo: potentially reverse the type_specs here

    if Enum.member?(@debug, :before) do
      show_function_signatures(env.module)
    end

    spec_errors = Module.get_attribute(env.module, :spec_errors)

    if (err_count = length(spec_errors)) > 0 do
      out =
        for err <- spec_errors, reduce: "" do
          acc -> acc <> "#{inspect(err)}\n"
        end

      Logger.error(out)
      throw({:phase_1, "#{err_count} errors you need to fix"})
    end
  end

  @doc """
  Called by Hook at `@after_compile`.
  """
  def handle_after_compile(env, bytecode) do
    all_module_definitions = fetch_module_definitions!(bytecode)

    delta_M = Module.get_attribute(env.module, :delta_M)
    delta_m = Utils.Env.get_map(env.module, :delta_M)

    delta_I = Module.get_attribute(env.module, :delta_I)
    delta_i = Utils.Env.get_map(env.module, :delta_I)

    psi = Utils.Env.get_map(env.module, :psi)

    module_init_handlers = Delta.key_set(delta_I)
    module_handlers = Delta.key_set(delta_M)

    errors =
      for {func_id, _kind, _meta, func_clauses} <- all_module_definitions, reduce: [] do
        acc ->
          cond do
            MapSet.member?(module_handlers, func_id) ->
              {handler_name, 4} = func_id

              handler_M = delta_m[handler_name]
              type_signatures = psi[func_id] |> Enum.reverse()

              res =
                for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                  TC.check_wf_message_handler_clause(
                    env.module,
                    handler_name,
                    clause,
                    handler_M.st,
                    type_signature
                  )
                  |> case do
                    {_status, %Maty.ST.SBranch{}} -> :ok
                    {:error, error_msg} -> error_msg
                  end
                end
                |> Enum.reject(&(&1 == :ok))
                |> Enum.map(&{func_id, &1})

              if(length(func_clauses) != length(handler_M.st.branches)) do
                visited_branches =
                  for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                    TC.check_wf_message_handler_clause(
                      env.module,
                      handler_name,
                      clause,
                      handler_M.st,
                      type_signature
                    )
                    |> case do
                      {:ok, %Maty.ST.SBranch{} = branch} -> branch
                      {:error, _msg} -> :error
                    end
                  end
                  |> Enum.reject(&(&1 == :error))
                  |> MapSet.new()

                missing_branches =
                  handler_M.st.branches
                  |> MapSet.new()
                  |> MapSet.difference(visited_branches)
                  |> MapSet.to_list()

                missing_st = Maty.ST.repr(%{handler_M.st | branches: missing_branches})

                error_msg =
                  Error.ProtocolViolation.incorrect_choice_implementation(
                    env.module,
                    handler_name,
                    missing_st,
                    handler_M.st
                  )

                [{func_id, error_msg} | acc]
              else
                res ++ acc
              end

            func_id == {:on_link, 2} ->
              type_signatures = psi[func_id] |> Enum.reverse()

              with {:clause, [clause]} <- {:clause, func_clauses},
                   {:signature, [type_signature]} <- {:signature, type_signatures} do
                TC.check_wf_on_link_callback(
                  env.module,
                  clause,
                  type_signature
                )
                |> case do
                  :ok -> acc
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

            MapSet.member?(module_init_handlers, func_id) ->
              {handler_name, 3} = func_id

              handler_I = delta_i[handler_name]
              type_signatures = psi[func_id] |> Enum.reverse()

              res =
                for {clause, type_signature} <- Enum.zip(func_clauses, type_signatures) do
                  TC.check_wf_init_handler_clause(
                    env.module,
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

              res ++ acc

            true ->
              res =
                TC.check_wf_function(env.module, func_id, func_clauses)
                |> Enum.reject(&match?({:ok, _}, &1))
                |> Enum.map(fn {:error, error_msg} -> {func_id, error_msg} end)

              res ++ acc
          end
      end

    if length(errors) != 0 do
      for err <- errors do
        if Enum.member?(@debug, :verbose) do
          Logger.error("\n[#{env.module}] #{display_error(err)}")
        else
          {_, error_msg} = err
          Logger.error(error_msg, ansi_color: :light_red)
        end
      end
    else
      Logger.info("\n[#{env.module}] No communication errors", ansi_color: :light_green)
    end
  end

  def fetch_module_definitions!(bytecode) do
    read_debug_info!(bytecode)
    |> Map.fetch!(:definitions)
    |> Enum.reject(fn x -> Keyword.get(elem(x, 2), :context) == Maty.Actor end)
  end

  # # Function to read debug information from bytecode.
  # #
  # # Adapted from: https://github.com/gertab/ElixirST by Gerard Tabone
  # # License: GPL-3.0 license
  @spec read_debug_info!(binary()) :: map() | no_return()
  defp read_debug_info!(bytecode) do
    try do
      try do
        chunks =
          case :beam_lib.chunks(bytecode, [:debug_info]) do
            {:ok, {_mod, chunks}} -> chunks
            {:error, _, error} -> throw({:error, inspect(error)})
          end

        # Gets the (extended) Elixir abstract syntax tree from debug_info chunk
        case chunks[:debug_info] do
          {:debug_info_v1, :elixir_erl, metadata} ->
            case metadata do
              {:elixir_v1, map, _} -> map
              {version, _, _} -> throw({:error, Error.version_mismatch(:elixir_v1, version)})
            end

          x ->
            throw({:error, inspect(x)})
        end
      catch
        _ -> throw({:error, :oops})
      end
    catch
      :error, error ->
        throw({:error, inspect(error)})
    end
  end

  # defp log_typechecking_results(func_id, res, label: label) do
  #   out = fn x -> "#{label}: #{inspect(func_id)}\n#{inspect(x)}" end

  #   for clause_res <- res do
  #     case clause_res do
  #       {:error, error} -> out.(error) |> Logger.error()
  #       {:ok, return} -> out.(return) |> Logger.debug()
  #     end
  #   end
  # end

  # defp extract_errors(res) do
  #   case res do
  #     {:ok, _} ->
  #       []

  #     {:error, error} ->
  #       [error]

  #     list when is_list(list) ->
  #       Enum.flat_map(list, fn
  #         {:ok, _} -> []
  #         {:error, error} -> [error]
  #       end)
  #   end
  # end

  defp show_function_signatures(module) do
    attr = Module.get_attribute(module, :psi)

    module_header =
      "\n-------------------- #{inspect(module)} -------------------"

    display =
      Enum.map_join(attr, "\n\n", fn {k, v} ->
        "#{inspect(k)} --> \n#{inspect(v)}"
      end)

    IO.puts(module_header <> "\n" <> display <> "\n")
  end

  def display_error({func_id, error_msg}) do
    "[#{Utils.to_func(func_id)}] #{error_msg}"
  end

  def stack_trace(num, extra \\ ""),
    do: Logger.debug("[#{num}] #{extra}", ansi_color: :light_blue)
end
