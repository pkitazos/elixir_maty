defmodule Maty.Typechecker.Preprocessor do
  require Logger

  alias Maty.Typechecker.TypeSpecParser
  alias Maty.Typechecker.Error
  alias Maty.Utils

  # each handler definition includes valuable information that we will need when we are typechecking our actors
  # the ast gives us a whole bunch of interesting stuff here
  # we're mainly interested in associating a session type with a handler name
  # so we give our pre-processor access to:
  # - the module
  # - the function ID
  # - the handler name (label)
  # - the available session types in scope
  # - our handler store directly (rather than having to fetch it from the environment)
  # - the kind of handler we're dealing with (message or init, I think)
  # - and the meta information (line number, etc.)
  def process_handler_annotation(
        module: module,
        function: {name, arity},
        handler_label: handler_label,
        session_types: session_types,
        store: handler_store,
        kind: handler_kind,
        meta: meta
      ) do
    # we perform some cursory checks, does a session type exist under such a name? and can we parse it?
    with {:ok, session_type} <- Map.fetch(session_types, handler_label),
         {:ok, st} <- Maty.Parser.parse(session_type) do
      # if both checks succeed, then we can associate the correct function under this handler label in the store
      Utils.Env.add_at_key(
        module,
        handler_store,
        handler_label,
        %{function: {name, arity}, st: st}
      )
    else
      # otherwise, depending on the error we either report that this is not a valid name for a handler
      :error ->
        error = Error.missing_handler(handler_label, meta)
        Logger.error(error)
        {:error, error}

      # or that we were not able to parse the session type
      {:error, parse_error} ->
        # ! it appears that this function expects to receive ane error struct, but instead receives a string
        error =
          Error.TypeSpecification.invalid_session_type_annotation(
            module,
            meta,
            handler_label,
            parse_error
          )

        Logger.error(error)
        {:error, error}
    end

    # and then we delete this attribute from the module
    Module.delete_attribute(module, handler_kind)
  end

  # each definition also requires a type-spec annotation

  def process_type_annotation(module: module, function: func_id = {name, args}) do
    # we fetch the spec definitions associated with the function we're typechecking
    case Module.get_attribute(module, :spec) do
      [{:spec, {:"::", meta, [{spec_name, _, args_asts}, return_ast]}, _module} | _] ->
        arity = length(args)

        # we check that:
        # - the arity and name match
        # - the args are typed properly
        # - the return type is parsed properly
        with {:info, {^name, ^arity}} <- {:info, {spec_name, length(args_asts)}},
             {:args_ok, parsed_arg_types} <-
               {:args_ok, parse_spec_args(args_asts)},
             {:return_ok, {:ok, parsed_return_type}} <-
               {:return_ok, TypeSpecParser.parse(return_ast)} do
          # if all looks good, we save the info to our Ψ environment
          Utils.Env.prepend_to_key(
            module,
            :psi,
            {name, arity},
            {parsed_arg_types, parsed_return_type}
          )

          Module.delete_attribute(module, :spec)
        else
          {:info, _} ->
            # otherwise we report the appropriate error
            error =
              Error.TypeSpecification.function_spec_info_mismatch(
                module,
                meta,
                spec_id: {spec_name, length(args_asts)},
                func_id: func_id
              )

            Logger.error(error)
            Module.put_attribute(module, :spec_errors, {{name, arity}, error})

          {:args_ok, {:error, {failed_index, internal_error}}} ->
            # in this particular point, because any one of the arguments could be malformed,
            # we return the index of those arguments so as to give the user more info
            error =
              Error.TypeSpecification.spec_args_parse_error_at(
                module,
                meta,
                func_id,
                failed_index,
                args_asts,
                internal_error
              )

            Logger.error(error)
            Module.put_attribute(module, :spec_errors, {{name, arity}, error})

          {:return_ok, {:error, parse_error}} ->
            error =
              Error.TypeSpecification.spec_return_not_well_typed(
                module,
                meta,
                spec_name,
                return_ast,
                parse_error
              )

            Logger.error(error)
            Module.put_attribute(module, :spec_errors, {{name, arity}, error})

          # this branch should not be reachable
          unreachable ->
            error = Error.internal_error(func_id, unreachable)

            Logger.error(error)
            Module.put_attribute(module, :spec_errors, {{name, arity}, error})
        end

      # this branch should also be unreachable
      # if we get anything other than a correct spec annotation, we return silently
      _ ->
        :ok
    end
  end

  @spec parse_spec_args(Macro.t()) :: list(Type.t()) | {:error, Error.Internal.t()}
  defp parse_spec_args(asts) do
    parsed_results = Enum.map(asts, &TypeSpecParser.parse/1)
    failed_index = Enum.find_index(parsed_results, fn res -> match?({:error, _}, res) end)

    if is_nil(failed_index) do
      Enum.map(parsed_results, fn {:ok, type} -> type end)
    else
      {:error, parsed_error} = Enum.at(parsed_results, failed_index)
      {:error, {failed_index, parsed_error}}
    end
  end
end
