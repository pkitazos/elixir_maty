defmodule Maty.DSL.Pattern do
  @moduledoc false

  # this stuff maybe shouldn't live here

  defguardp is_supported_type(val)
            when is_atom(val) or
                   is_binary(val) or
                   is_boolean(val) or
                   is_number(val)

  # Process the pattern to strip type annotations and build a type spec
  def process_pattern({tag, payload}) when is_atom(tag) do
    {clean_payload, payload_type} = process_payload(payload)
    {{tag, clean_payload}, quote(do: {unquote(tag), unquote(payload_type)})}
  end

  # Case 1: Payload with type annotation
  def process_payload({:"::", _, [var, type]}) do
    {var, type}
  end

  # Case 2: 2-tuple of variables
  def process_payload({a, b}) do
    {a_clean, a_type} = process_var_with_type(a)
    {b_clean, b_type} = process_var_with_type(b)
    {{a_clean, b_clean}, quote(do: {unquote(a_type), unquote(b_type)})}
  end

  # Case 3: n-tuple of variables
  def process_payload({:{}, context, elements}) do
    {clean_elements, element_types} = Enum.unzip(Enum.map(elements, &process_var_with_type/1))
    {{:{}, context, clean_elements}, quote(do: {unquote_splicing(element_types)})}
  end

  # Case 4: List with type annotation
  def process_payload({:"::", _, [[_ | _] = list, list_type]}) do
    clean_vars =
      Enum.map(list, fn
        {var, _, ctx} when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) -> {var, [], ctx}
        # Handle literals or other values
        var -> var
      end)

    {clean_vars, list_type}
  end

  # Case 5: List without type annotation (default to list(any()))
  def process_payload(list) when is_list(list) do
    clean_vars =
      Enum.map(list, fn
        {var, _, ctx} when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) -> {var, [], ctx}
        # Handle literals or other values
        var -> var
      end)

    {clean_vars, quote(do: list(any()))}
  end

  # Case 6: Simple variable without type annotation
  def process_payload({var, meta, ctx}) when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) do
    {{var, meta, ctx}, quote(do: any())}
  end

  # Case 7: Literal value (number, string, atom, boolean)
  def process_payload(literal)
      when is_number(literal) or is_binary(literal) or is_atom(literal) or is_boolean(literal) do
    {literal, infer_type_from_literal(literal)}
  end

  # Default case - for any other pattern, we'll just leave it as is and use any() type
  # pin - this would be an error case in a stricter implementation
  def process_payload(other) do
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
  def process_init_pattern({:"::", _, [var, type]}) do
    # Direct type annotation case: title :: binary()
    {var, type}
  end

  def process_init_pattern({var, meta, ctx})
      when is_atom(var) and (is_atom(ctx) or is_nil(ctx)) do
    # Simple variable without type annotation: title
    {{var, meta, ctx}, quote(do: any())}
  end

  # Other cases can be handled similarly to process_payload
  def process_init_pattern(literal) when is_supported_type(literal) do
    {literal, infer_type_from_literal(literal)}
  end

  def process_init_pattern(other) do
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
