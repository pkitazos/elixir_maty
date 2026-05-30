defmodule Maty.DSL.Handlers do
  @type role :: Maty.Types.role()
  @type session_id :: Maty.Types.session_id()
  @type init_token :: Maty.Types.init_token()
  @type session_ctx :: Maty.Types.session_ctx()
  @type maty_actor_state :: Maty.Types.maty_actor_state()

  @moduledoc """
  Provides user-friendly macros for the Maty framework.

  These macros simplify the process of writing session-typed actors by providing
  a more declarative syntax for handlers and communication operations.
  """

  defmacro handler(handler_name, role, pattern, state_var, do: body) do
    # first verify we have a proper tagged tuple pattern
    # the pattern should be a 2-tuple with an atom tag as the first element
    case pattern do
      {tag, _payload} when is_atom(tag) ->
        # process the pattern to extract the cleaned pattern and type specification
        {clean_pattern, type_spec} = process_pattern(pattern)

        quote do
          @handler unquote(handler_name)
          @spec unquote(handler_name)(
                  unquote(role),
                  unquote(type_spec),
                  # make sure to update these guys
                  maty_actor_state(),
                  session_ctx()
                ) :: no_return()
          def unquote(handler_name)(
                unquote(role),
                unquote(clean_pattern),
                unquote(state_var),
                session_ctx
              ) do
            try do
              var!(session_ctx) = session_ctx

              # use the session_ctx variable so the LSP won't yell at me
              _ = var!(session_ctx)
              unquote(body)
            catch
              {:suspend, next_handler, new_state} -> {:suspend, next_handler, new_state}
              {:done, new_state} -> {:done, new_state}
            end
          end

          def __handler_expects__(unquote(handler_name)), do: unquote(role)
        end

      _ ->
        # ERROR: Expected a tagged tuple pattern like {:tag, payload}
        # for now, we'll just raise a compile-time error
        raise ArgumentError, "Expected a tagged tuple pattern like {:tag, payload}"
    end
  end

  defmacro init_handler(handler_name, pattern, state_var, do: body) do
    {clean_pattern, type_spec} = process_init_pattern(pattern)

    quote do
      @init_handler unquote(handler_name)
      @spec unquote(handler_name)(
              unquote(type_spec),
              # make sure to update these guys
              maty_actor_state(),
              session_ctx()
            ) :: no_return()
      def unquote(handler_name)(
            unquote(clean_pattern),
            unquote(state_var),
            session_ctx
          ) do
        try do
          var!(session_ctx) = session_ctx

          # use the session_ctx variable so the LSP won't yell at me
          _ = var!(session_ctx)
          unquote(body)
        catch
          {:suspend, next_handler, new_state} -> {:suspend, next_handler, new_state}
        end
      end
    end
  end

  defmacro on_link(pattern, initial_state_var, do: body) do
    {clean_pattern, type_spec} = process_init_pattern(pattern)

    quote do
      @impl true
      @spec on_link(unquote(type_spec), maty_actor_state()) :: {:ok, maty_actor_state()}
      def on_link(unquote(clean_pattern), unquote(initial_state_var)) do
        unquote(body)
      end
    end
  end

  defguardp is_supported_type(val)
            when is_atom(val) or
                   is_binary(val) or
                   is_boolean(val) or
                   is_number(val)

  # Process the pattern to strip type annotations and build a type spec
  defp process_pattern({tag, payload}) when is_atom(tag) do
    {clean_payload, payload_type} = process_payload(payload)
    {{tag, clean_payload}, quote(do: {unquote(tag), unquote(payload_type)})}
  end

  # Case 1: Payload with type annotation
  defp process_payload({:"::", _, [var, type]}) do
    {var, type}
  end

  # Case 2: 2-tuple of variables
  defp process_payload({a, b}) do
    {a_clean, a_type} = process_var_with_type(a)
    {b_clean, b_type} = process_var_with_type(b)
    {{a_clean, b_clean}, quote(do: {unquote(a_type), unquote(b_type)})}
  end

  # Case 3: n-tuple of variables
  defp process_payload({:{}, context, elements}) do
    {clean_elements, element_types} = Enum.unzip(Enum.map(elements, &process_var_with_type/1))
    {{:{}, context, clean_elements}, quote(do: {unquote_splicing(element_types)})}
  end

  # Case 4: List with type annotation
  defp process_payload({:"::", _, [[_ | _] = list, list_type]}) do
    clean_vars =
      Enum.map(list, fn
        {var, _, ctx} when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) -> {var, [], ctx}
        # Handle literals or other values
        var -> var
      end)

    {clean_vars, list_type}
  end

  # Case 5: List without type annotation (default to list(any()))
  defp process_payload(list) when is_list(list) do
    clean_vars =
      Enum.map(list, fn
        {var, _, ctx} when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) -> {var, [], ctx}
        # Handle literals or other values
        var -> var
      end)

    {clean_vars, quote(do: list(any()))}
  end

  # Case 6: Simple variable without type annotation
  defp process_payload({var, meta, ctx}) when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) do
    {{var, meta, ctx}, quote(do: any())}
  end

  # Case 7: Literal value (number, string, atom, boolean)
  defp process_payload(literal)
       when is_number(literal) or is_binary(literal) or is_atom(literal) or is_boolean(literal) do
    {literal, infer_type_from_literal(literal)}
  end

  # Default case - for any other pattern, we'll just leave it as is and use any() type
  # pin - this would be an error case in a stricter implementation
  defp process_payload(other) do
    {other, quote(do: any())}
  end

  # Helper to process a variable that might have a type annotation
  defp process_var_with_type({:"::", _, [var, type]}) do
    {var, type}
  end

  defp process_var_with_type({var, meta, ctx})
       when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) do
    {{var, meta, ctx}, quote(do: any())}
  end

  defp process_var_with_type(literal)
       when is_number(literal) or is_binary(literal) or is_atom(literal) or is_boolean(literal) do
    {literal, infer_type_from_literal(literal)}
  end

  defp process_var_with_type(other) do
    # This would be an error case in a stricter implementation
    {other, quote(do: any())}
  end

  # New helper for init_handler patterns
  defp process_init_pattern({:"::", _, [var, type]}) do
    # Direct type annotation case: title :: binary()
    {var, type}
  end

  defp process_init_pattern({var, meta, ctx})
       when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) do
    # Simple variable without type annotation: title
    {{var, meta, ctx}, quote(do: any())}
  end

  # Other cases can be handled similarly to process_payload
  defp process_init_pattern(literal) when is_supported_type(literal) do
    {literal, infer_type_from_literal(literal)}
  end

  defp process_init_pattern(other) do
    # For more complex patterns, we could delegate to process_payload
    process_payload(other)
  end

  # Helper to infer a type from a literal value
  defp infer_type_from_literal(literal) do
    cond do
      is_binary(literal) -> quote(do: binary())
      is_integer(literal) -> quote(do: number())
      is_float(literal) -> quote(do: number())
      is_boolean(literal) -> quote(do: boolean())
      is_nil(literal) -> quote(do: nil)
      is_atom(literal) -> quote(do: atom())
      true -> quote(do: any())
    end
  end
end
