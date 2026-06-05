defmodule Maty.Typechecker.Preprocessor do
  @moduledoc """
  Compile-time processing of Maty handler and type-spec annotations.

  Runs while a `Maty.Actor` module is being compiled. As each handler and
  typed function is defined, the compile hook hands the accumulated module
  attributes here to be validated, parsed into the framework's internal
  representations, and stored for the typechecker to use later.

  There are two responsibilities:

    * **Handler annotations:** associate a parsed session type with the handler
      that implements it (`process_handler_annotation/1`).
    * **Type-spec annotations:** turn an `@spec` into parsed argument and
      return types recorded under the function id (`process_type_annotation/1`).

  They both consume module attributes (deleting them once handled) and write
  their results into the per-module environment via `Maty.Utils.Env`.
  Validation failures are logged; spec failures are additionally recorded
  in `:spec_errors` so the typechecker can report them to the user.
  """
  require Logger

  alias Maty.Typechecker.TypeSpecParser
  alias Maty.Typechecker.Error
  alias Maty.Types.T, as: Type
  alias Maty.Utils

  @doc """
  Validates a single handler annotation and registers it for the typechecker.

  Invoked by the compile hook once per annotated handler, with a map
  describing everything known about the definition at compile time.

  ## Fields

    * `:module` - the module currently being compiled
    * `:function` - the handler's `{name, arity}`
    * `:handler_label` - the message label the handler responds to / the key it is stored under
    * `:session_types` - the session types in scope, keyed by label
    * `:store` - the module attribute acting as the handler store to write into
    * `:kind` - which handler attribute is being consumed (e.g. message vs init)
    * `:meta` - source location used in error messages

  On success, stores `%{function: {name, arity}, st: parsed_session_type}`
  under `handler_label`. On failure the error is logged only.

  Either way the `:kind` attribute is deleted before returning, so this is
  called for its side effects.
  """
  @spec process_handler_annotation(%{
          required(:module) => module(),
          required(:function) => {atom(), arity()},
          required(:handler_label) => atom(),
          required(:session_types) => %{atom() => String.t()},
          required(:store) => atom(),
          required(:kind) => atom(),
          required(:meta) => keyword()
        }) :: :ok
  def process_handler_annotation(%{
        module: module,
        function: {name, arity},
        handler_label: handler_label,
        session_types: session_types,
        store: handler_store,
        kind: handler_kind,
        meta: meta
      }) do
    case validate_handler_annotation(module, handler_label, session_types, meta) do
      {:ok, st} ->
        Utils.Env.add_at_key(
          module,
          handler_store,
          handler_label,
          %{function: {name, arity}, st: st}
        )

      {:error, error} ->
        Logger.error(error)
    end

    # and then we delete this attribute from the module
    Module.delete_attribute(module, handler_kind)
    :ok
  end

  # Checks that `handler_label` names a session type in scope and that the
  # session type string parses. Returns `{:ok, parsed_st}`, or `{:error, e}`
  # where `e` describes either a missing handler label or a parse failure.
  @doc false
  @spec validate_handler_annotation(module(), atom(), %{atom() => String.t()}, keyword()) ::
          {:ok, Maty.ST.t()} | {:error, String.t()}
  def validate_handler_annotation(module, handler_label, session_types, meta) do
    # we perform some cursory checks, does a session type exist under such a name? and can we parse it?
    with {:ok, session_type} <- Map.fetch(session_types, handler_label),
         {:ok, st} <- Maty.Parser.parse(session_type) do
      {:ok, st}
    else
      # this is not a valid name for a handler
      :error ->
        {:error, Error.missing_handler(handler_label, meta)}

      # we were not able to parse the session type
      {:error, parse_error} ->
        {:error,
         Error.TypeSpecification.invalid_session_type_annotation(
           module,
           meta,
           handler_label,
           %Error.Internal{
             title: "Session type parse error",
             opts: "",
             message: parse_error
           }
         )}
    end
  end

  @doc """
  Validates a function's `@spec` and records its parsed type for the typechecker.

  Invoked by the compile hook for each typed definition. On success the
  parsed `{arg_types, return_type}` pair is prepended under the function id
  in the `:psi` environment and the `:spec` attribute is deleted.

  A validation error is logged and recorded under `:spec_errors`, so the
  typechecker can surface it later instead of the compilation aborting.
  When no spec is present the call is a no-op.
  """
  @spec process_type_annotation(%{
          required(:module) => module(),
          required(:function) => {atom(), [Macro.t()]}
        }) :: :ok
  def process_type_annotation(%{module: module, function: {name, args}}) do
    arity = length(args)
    func_id = {name, arity}
    spec_attr = Module.get_attribute(module, :spec)

    case validate_type_annotation(spec_attr, module, func_id) do
      {:ok, result} ->
        Utils.Env.prepend_to_key(module, :psi, func_id, result)
        Module.delete_attribute(module, :spec)

      {:error, error} ->
        Logger.error(error)
        Module.put_attribute(module, :spec_errors, {func_id, error})

      # TODO: distinguish functions that legitimately need no spec
      # (e.g. framework-generated callbacks) from ones that are just missing one
      :no_spec ->
        :ok
    end

    :ok
  end

  # Validates a `:spec` attribute against the function it should describe.
  #
  # Expects the raw attribute as returned by `Module.get_attribute(mod, :spec)`.
  # Confirms the spec's name and arity match `func_id`, then parses each
  # argument and the return type. Returns:
  #
  #   * `{:ok, {arg_types, return_type}}` - name/arity match and everything parses
  #   * `{:error, e}` - a name/arity mismatch, an argument that fails to parse
  #     (carrying its position), or an unparseable return type
  #   * `:no_spec` - `spec_attr` isn't a recognised spec form (e.g. `nil`)
  @doc false
  @spec validate_type_annotation(term(), module(), {atom(), arity()}) ::
          {:ok, {[Type.t()], Type.t()}} | {:error, String.t()} | :no_spec
  def validate_type_annotation(spec_attr, module, func_id = {name, arity}) do
    case spec_attr do
      [{:spec, {:"::", meta, [{spec_name, _, args_asts}, return_ast]}, _module} | _] ->
        # we check that:
        # - the arity and name match
        # - the args are typed properly
        # - the return type is parsed properly
        with {:info, {^name, ^arity}} <- {:info, {spec_name, length(args_asts)}},
             {:args, {:ok, parsed_arg_types}} <- {:args, parse_spec_args(args_asts)},
             {:return, {:ok, parsed_return_type}} <- {:return, TypeSpecParser.parse(return_ast)} do
          {:ok, {parsed_arg_types, parsed_return_type}}
        else
          {:info, _} ->
            {:error,
             Error.TypeSpecification.function_spec_info_mismatch(
               module,
               meta,
               spec_id: {spec_name, length(args_asts)},
               func_id: func_id
             )}

          {:args, {:error, {failed_index, internal_error}}} ->
            {:error,
             Error.TypeSpecification.spec_args_parse_error_at(
               module,
               meta,
               func_id,
               failed_index,
               args_asts,
               internal_error
             )}

          {:return, {:error, parse_error}} ->
            {:error,
             Error.TypeSpecification.spec_return_not_well_typed(
               module,
               meta,
               spec_name,
               return_ast,
               parse_error
             )}
        end

      _ ->
        :no_spec
    end
  end

  # Parses a list of argument type ASTs left-to-right.
  #
  # Returns `{:ok, types}` in source order, or halts on the first failure with
  # `{:error, {index, internal_error}}`, where `index` is the position of the bad arg.
  @doc false
  @spec parse_spec_args([Macro.t()]) ::
          {:ok, [Type.t()]} | {:error, {non_neg_integer(), Error.Internal.t()}}
  def parse_spec_args(asts) do
    asts
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {ast, idx}, acc ->
      case TypeSpecParser.parse(ast) do
        {:ok, type} -> {:cont, [type | acc]}
        {:error, err} -> {:halt, {:error, {idx, err}}}
      end
    end)
    |> case do
      {:error, _} = err -> err
      types -> {:ok, Enum.reverse(types)}
    end
  end
end
