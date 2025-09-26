defmodule Maty.Typechecker.TC do
  require Logger

  alias Maty.{ST, Utils}
  alias Maty.Types.T, as: Type
  alias Maty.Typechecker.{Error, Helpers}

  import Maty.Typechecker.PatternBinding, only: [tc_pattern: 4]
  import Maty.Utils, only: [stack_trace: 1]

  @typedoc """
  Represents Elixir AST nodes that can be typechecked.
  """
  @type ast :: Macro.t()

  @typedoc """
  Environment mapping variable names to their types.
  Used to track types of variables during typechecking.
  """
  @type var_env() :: %{atom() => Type.t()}
  @doc """
  Typechecks an expression AST node within a given variable environment and
  session state pre-condition.

  Corresponds to the formal judgement: Ψ; Δ; Γ ∣ Q₁ ⊳ e : T ⊲ Q₂

  Returns:
    - `{:ok, {elixir_type, next_session_state}, var_env}` on success
    - `{:error, error_message, var_env}` on failure
  """
  @spec tc_expr(module :: module(), var_env :: var_env(), st_pre :: ST.t(), ast :: ast()) ::
          {:ok, {Type.t(), ST.t()}, var_env()} | {:error, binary(), var_env()}

  # --- Revised Value Typing Clauses ---

  # Base Literals (Val-BaseLit adaptation)
  # These are pure values; they preserve the current session state.
  def tc_expr(_module, var_env, st_pre, value) when is_boolean(value) do
    stack_trace(0)
    {:ok, {:boolean, st_pre}, var_env}
  end

  def tc_expr(
        _module,
        var_env,
        st_pre,
        {:when, _,
         [
           {:x, _, Kernel},
           {{:., _, [:erlang, :orelse]}, _,
            [
              {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, false]},
              {{:., _, [:erlang, :"=:="]}, _, [{:x, _, Kernel}, nil]}
            ]}
         ]}
      ) do
    stack_trace(00)
    {:ok, {:boolean, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, nil) do
    stack_trace(0)
    {:ok, {nil, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, value) when is_binary(value) do
    stack_trace(0)
    {:ok, {:binary, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, value) when is_number(value) do
    stack_trace(0)
    {:ok, {:number, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, value) when is_pid(value) do
    stack_trace(0)
    {:ok, {:pid, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, value) when is_reference(value) do
    stack_trace(0)
    {:ok, {:ref, st_pre}, var_env}
  end

  # Date Literal check (example, assuming Date struct exists)
  def tc_expr(_module, var_env, st_pre, {:%, _, [Date, {:%{}, _, _}]}) do
    stack_trace(0)
    {:ok, {:date, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, {{:., _, [{:__aliases__, _, [:Date]}, :t]}, _, []}) do
    stack_trace(0)
    {:ok, {:date, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, {:no_return, _meta, []}) do
    stack_trace(0)
    {:ok, {:no_return, st_pre}, var_env}
  end

  def tc_expr(_module, var_env, st_pre, {:any, _meta, []}) do
    stack_trace(0)
    {:ok, {:any, st_pre}, var_env}
  end

  # todo: either add support for keyword lists or make this just work properly
  # as in this part of the register macro could either straight up expand to an anonymous function
  # or it could require a list of 2-tuples where
  # the first element is a tagged tuple containing an atom which maps to a handler
  # and the second element is a tagged tuple containing a list of arguments of whatever type
  # and the types need to match the type of the handler somehow?

  # --- Init Handler reference (Keyword list is technically a List)---
  # Handles passing a reference to an init_handler when registering
  def tc_expr(module, var_env, st_pre, [callback: init_handler, args: args_ast] = _ast)
      when is_list(args_ast) do
    stack_trace(202)
    delta_I = Utils.Env.get_map(module, :delta_I)

    if Map.has_key?(delta_I, init_handler) do
      {:ok, {{:fun, length(args_ast)}, st_pre}, var_env}
    else
      # pin - convert to new kind of error
      {:error, "Trying to register with invalid init_handler", var_env}
    end
  end

  def tc_expr(module, var_env, st_pre, [callback: init_handler, args: args_ast] = _ast)
      when is_nil(args_ast) do
    stack_trace(202)
    delta_I = Utils.Env.get_map(module, :delta_I)

    if Map.has_key?(delta_I, init_handler) do
      {:ok, {{:fun, 0}, st_pre}, var_env}
    else
      # pin - convert to new kind of error
      {:error, "Trying to register with invalid init_handler", var_env}
    end
  end

  def tc_expr(module, var_env, st_pre, [callback: init_handler] = _ast) do
    stack_trace(202)
    delta_I = Utils.Env.get_map(module, :delta_I)

    if Map.has_key?(delta_I, init_handler) do
      {:ok, {{:fun, 0}, st_pre}, var_env}
    else
      # pin - convert to new kind of error
      {:error, "Trying to register with invalid init_handler", var_env}
    end
  end

  # List Construction [v1, v2, ...] (Val-Cons / Val-EmptyList adaptation)
  # Enforces homogeneity. Preserves session state.
  def tc_expr(_module, var_env, st_pre, []) do
    stack_trace(1)
    {:ok, {{:list, :any}, st_pre}, var_env}
  end

  def tc_expr(module, var_env, st_pre, items) when is_list(items) do
    stack_trace(1)

    # Process list elements sequentially
    Enum.reduce_while(
      items,
      {:ok, {[], st_pre}, var_env},
      fn item, {:ok, {acc_types, current_st}, current_env} ->
        case tc_expr(module, current_env, current_st, item) do
          {:ok, {item_type, next_st}, next_env} ->
            {:cont, {:ok, {[item_type | acc_types], next_st}, next_env}}

          {:error, error, err_env} ->
            {:halt, {:error, error, err_env}}
        end
      end
    )
    |> case do
      {:ok, {types_rev, final_st}, final_env} ->
        element_type = types_rev |> Enum.reverse() |> Helpers.unify_list_types()

        if element_type == :error_incompatible do
          # todo: add meta information to the error if possible
          meta = []

          {:error,
           Error.TypeMismatch.list_elements_incompatible(module, meta, Enum.reverse(types_rev)),
           final_env}
        else
          {:ok, {{:list, element_type}, final_st}, final_env}
        end

      {:error, error, err_env} ->
        {:error, error, err_env}
    end
  end

  # Empty Tuple (Val-EmptyTuple adaptation)
  # Preserves session state.
  def tc_expr(_module, var_env, st_pre, {:{}, _, []}) do
    stack_trace(2)
    {:ok, {{:tuple, []}, st_pre}, var_env}
  end

  # --- 2-Tuple Value Construction ---
  # Handles literal 2-tuples {v1, v2} explicitly, distinct from n-tuples {:{}, _, [...]} in the AST
  def tc_expr(module, var_env, st_pre, {v1_ast, v2_ast}) do
    stack_trace(2)

    with {:v1, {:ok, {v1_t, v1_st}, v1_env}} <- {:v1, tc_expr(module, var_env, st_pre, v1_ast)},
         {:v2, {:ok, {v2_t, v2_st}, v2_env}} <- {:v2, tc_expr(module, v1_env, v1_st, v2_ast)} do
      {:ok, {{:tuple, [v1_t, v2_t]}, v2_st}, v2_env}
    else
      {:v1, {:error, error, err_env}} -> {:error, error, err_env}
      {:v2, {:error, error, err_env}} -> {:error, error, err_env}
    end
  end

  # n-Tuple Construction {v1, v2, ...} (Val-Tuple adaptation)
  # Preserves session state.
  def tc_expr(module, var_env, st_pre, {:{}, _, items}) when is_list(items) do
    stack_trace(2)
    # Process tuple elements sequentially, threading env and state
    Enum.reduce_while(
      items,
      {:ok, {[], st_pre}, var_env},
      fn item, {:ok, {acc_types, current_st}, current_env} ->
        case tc_expr(module, current_env, current_st, item) do
          {:ok, {item_type, next_st}, next_env} ->
            {:cont, {:ok, {[item_type | acc_types], next_st}, next_env}}

          {:error, error, err_env} ->
            {:halt, {:error, error, err_env}}
        end
      end
    )
    |> case do
      {:ok, {types_rev, final_st}, final_env} ->
        # Formal: Tuple[A1, ..., An]
        {:ok, {{:tuple, Enum.reverse(types_rev)}, final_st}, final_env}

      {:error, error, err_env} ->
        {:error, error, err_env}
    end
  end

  # Map Construction %{k1 => v1, ...} (Val-Map / Val-EmptyMap adaptation)
  # Allows heterogeneous value types, deviates slightly from our formalisation
  def tc_expr(_module, var_env, st_pre, {:%{}, _, []}) do
    stack_trace(3)
    {:ok, {{:map, %{}}, st_pre}, var_env}
  end

  # Clause for Non-Empty Map %{k1 => v1, ...}
  def tc_expr(module, var_env, st_pre, {:%{}, meta, pairs}) when is_list(pairs) do
    stack_trace(3)

    Enum.reduce_while(
      pairs,
      {:ok, {%{}, st_pre}, var_env},
      fn {key_ast, value_ast}, {:ok, {acc_type_map, current_st}, current_env} ->
        case tc_expr(module, current_env, current_st, key_ast) do
          {:ok, {key_type, key_st}, key_env} ->
            if key_type == :atom do
              literal_key = Helpers.ast_to_literal(key_ast)

              # todo: this whole thing needs cleaning up tbh
              # Check if the key AST could be converted to a literal atom
              if is_atom(literal_key) do
                # 4. Typecheck the value AST (using state and env from key check)
                case tc_expr(module, key_env, key_st, value_ast) do
                  {:ok, {value_type, value_st}, value_env} ->
                    # Key is valid atom, value typechecked successfully.
                    # Store value_type using the actual literal key in the result type map.
                    updated_map = Map.put(acc_type_map, literal_key, value_type)
                    # Continue reduction with updated map, latest state, and env.
                    {:cont, {:ok, {updated_map, value_st}, value_env}}

                  {:error, error, err_env} ->
                    # Value typechecking failed, halt the reduction.
                    {:halt, {:error, error, err_env}}
                end
              else
                # Key AST was type :atom but couldn't be converted to a literal atom (e.g., complex expression resulting in an atom)
                # Or Helpers.ast_to_literal returned an error indicator.
                # We require literal atom keys.
                # Error for non-literal atom key
                error = Error.PatternMatching.complex_map_key(module, meta, key_ast)
                {:halt, {:error, error, key_env}}
              end
            else
              # Key type check failed (key_type was not :atom).
              error =
                Error.PatternMatching.invalid_map_key_type(module, meta,
                  expected: :atom,
                  got: key_type
                )

              # Halt the reduction.
              {:halt, {:error, error, key_env}}
            end

          {:error, error, err_env} ->
            # Key typechecking failed (error occurred during tc_expr on key_ast).
            # Halt the reduction.
            {:halt, {:error, error, err_env}}
        end
      end
    )
    |> case do
      {:ok, {type_map, final_st}, final_env} ->
        # Resulting type is {:map, %{key_literal => value_type, ...}}
        {:ok, {{:map, type_map}, final_st}, final_env}

      # Reduction was halted due to an error
      {:error, error, err_env} ->
        {:error, error, err_env}
    end
  end

  # --- Logical Not Operator (T-Not) ---

  def tc_expr(module, var_env, st_pre, {{:., meta, [:erlang, :not]}, _, [operand_ast]}) do
    stack_trace(6)

    case tc_expr(module, var_env, st_pre, operand_ast) do
      {:ok, {:boolean, operand_st}, operand_env} ->
        {:ok, {:boolean, operand_st}, operand_env}

      {:ok, {other_type, _operand_st}, operand_env} ->
        error =
          Error.TypeMismatch.logical_operator_requires_boolean(module, meta, :not, other_type)

        {:error, error, operand_env}

      {:error, error, err_env} ->
        {:error, error, err_env}
    end
  end

  # --- Binary Operators (T-Op) ---

  # Handles Arithmetic and Comparison Ops: +, -, *, /, <, >, <=, >=, ==, !=
  def tc_expr(module, var_env, st_pre, {{:., meta, [:erlang, op]}, _, [lhs_ast, rhs_ast]})
      when op in [:+, :-, :*, :/, :<, :>, :<=, :>=, :==, :!=] do
    stack_trace(7)

    with {:lhs, {:ok, {lhs_type, lhs_st}, lhs_env}} <-
           {:lhs, tc_expr(module, var_env, st_pre, lhs_ast)},
         {:rhs, {:ok, {rhs_type, rhs_st}, rhs_env}} <-
           {:rhs, tc_expr(module, lhs_env, lhs_st, rhs_ast)},
         # pin - maybe helper could return more standard type
         {:op_check, {:ok, result_type}, _} <-
           {:op_check, Helpers.op_type_rel(op, lhs_type, rhs_type), [lhs_type, rhs_type, rhs_env]} do
      {:ok, {result_type, rhs_st}, rhs_env}
    else
      {:lhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:rhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:op_check, :error, [lhs_type, rhs_type, rhs_env]} ->
        error =
          Error.TypeMismatch.binary_operator_type_mismatch(module, meta, op, lhs_type, rhs_type)

        {:error, error, rhs_env}
    end
  end

  # Handles String Concatenation: <>

  def tc_expr(
        module,
        var_env,
        st_pre,
        {:<<>>, meta, [{:"::", _, [lhs_ast, _]}, {:"::", _, [rhs_ast, _]}]}
      ) do
    stack_trace(8)

    with {:lhs, {:ok, {lhs_type, lhs_st}, lhs_env}} <-
           {:lhs, tc_expr(module, var_env, st_pre, lhs_ast)},
         {:rhs, {:ok, {rhs_type, rhs_st}, rhs_env}} <-
           {:rhs, tc_expr(module, lhs_env, lhs_st, rhs_ast)},
         # pin - maybe helper could return more standard type
         {:op_check, {:ok, result_type}, _} <-
           {:op_check, Helpers.op_type_rel(:<>, lhs_type, rhs_type),
            [lhs_type, rhs_type, rhs_env]} do
      {:ok, {result_type, rhs_st}, rhs_env}
    else
      {:lhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:rhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:op_check, :error, [lhs_type, rhs_type, rhs_env]} ->
        error =
          Error.TypeMismatch.binary_operator_type_mismatch(module, meta, :<>, lhs_type, rhs_type)

        {:error, error, rhs_env}
    end
  end

  # Handles Boolean Ops: and, or
  def tc_expr(module, var_env, st_pre, {op, meta, [lhs_ast, rhs_ast]})
      when op in [:and, :or] do
    stack_trace(9)

    with {:lhs, {:ok, {lhs_type, lhs_st}, lhs_env}} <-
           {:lhs, tc_expr(module, var_env, st_pre, lhs_ast)},
         {:rhs, {:ok, {rhs_type, rhs_st}, rhs_env}} <-
           {:rhs, tc_expr(module, lhs_env, lhs_st, rhs_ast)},
         # pin - maybe helper could return more standard type
         {:op_check, {:ok, result_type}, _} <-
           {:op_check, Helpers.op_type_rel(op, lhs_type, rhs_type), [lhs_type, rhs_type, rhs_env]} do
      {:ok, {result_type, rhs_st}, rhs_env}
    else
      {:lhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:rhs, {:error, msg, env}} ->
        {:error, msg, env}

      {:op_check, :error, [lhs_type, rhs_type, rhs_env]} ->
        error =
          Error.TypeMismatch.logical_operator_type_mismatch(module, meta, op, lhs_type, rhs_type)

        {:error, error, rhs_env}
    end
  end

  # --- Raw Communication Checks ---

  # Disallow raw 'receive'
  def tc_expr(_module, var_env, _st_pre, {:receive, meta, _}) do
    stack_trace(11)
    # pin - convert to new kind of error
    {:error, Error.no_raw_receive(meta), var_env}
  end

  # Disallow raw 'send' (Kernel.send/2 or :erlang.send/2)
  def tc_expr(_module, var_env, _st_pre, {{:., meta, [:erlang, :send]}, _, args})
      when length(args) in [2, 3] do
    stack_trace(12)
    # pin - convert to new kind of error
    {:error, Error.no_raw_send(meta), var_env}
  end

  # Check for Kernel.send/2
  def tc_expr(_module, var_env, _st_pre, {{:., meta, [:Kernel, :send]}, _, args})
      when length(args) == 2 do
    stack_trace(13)
    # pin - convert to new kind of error
    {:error, Error.no_raw_send(meta), var_env}
  end

  # --- Anonymous Functions and Captures ---
  # todo: these are a bit rudimentary
  # for proper typechecking of anonymous functions and/or captures we may need to either introduce more syntax
  # or change the typechecker to use constraints and unification

  # Anonymous function: fn args -> ... end
  def tc_expr(_module, var_env, st_pre, {:fn, _meta, [{:->, _, [args_ast, _body_ast]}]}) do
    stack_trace(14)
    arity = length(args_ast)
    {:ok, {{:fun, arity}, st_pre}, var_env}
  end

  # Remote function capture: &Mod.fun/arity
  def tc_expr(
        _module,
        var_env,
        st_pre,
        {:&, _meta, [{:/, _, [{{:., _, [_mod, _fun]}, _, _}, arity]}]}
      )
      when is_integer(arity) do
    stack_trace(15)
    {:ok, {{:fun, arity}, st_pre}, var_env}
  end

  # Local function capture: &fun/arity
  def tc_expr(_module, var_env, st_pre, {:&, _meta, [{:/, _, [fun_atom, arity]}]})
      when is_atom(fun_atom) and is_integer(arity) do
    stack_trace(16)
    {:ok, {{:fun, arity}, st_pre}, var_env}
  end

  # --- Block Scope ---
  def tc_expr(module, var_env, st_pre, {:__block__, _, body_asts}) when is_list(body_asts) do
    stack_trace(17)
    tc_expr_list(module, var_env, st_pre, body_asts)
  end

  # Computation Typing

  # --- Let Expression / Match Operator (T-Let) ---
  # Represents `pattern = expr1`
  def tc_expr(module, var_env, st_pre, {:=, _meta, [pattern_ast, expr1_ast]}) do
    stack_trace(18)

    with {:e1, {:ok, {type_A, st_post_e1}, env_post_e1}} <-
           {:e1, tc_expr(module, var_env, st_pre, expr1_ast)},
         #  todo not sure about the naming of the atoms here
         {:p_match, {:ok, _new_bindings, updated_env_with_bindings}} <-
           {:p_match, tc_pattern(module, pattern_ast, type_A, env_post_e1)} do
      {:ok, {type_A, st_post_e1}, updated_env_with_bindings}
    else
      {:e1, {:error, msg, env}} -> {:error, msg, env}
      {:p_match, {:error, msg, env}} -> {:error, msg, env}
    end
  end

  # --- Case Expression (T-Case) ---
  # AST: {:case, meta, [scrutinee_ast, [do: clauses_list]]}

  def tc_expr(module, var_env, st_pre, {:case, meta, [scrutinee_ast, [do: clauses_list]]}) do
    stack_trace(19)

    with {:scrutinee, {:ok, {type_A, st_after_scrutinee}, env_after_scrutinee}} <-
           {:scrutinee, tc_expr(module, var_env, st_pre, scrutinee_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(st_pre, st_after_scrutinee, meta) do
      # todo: this is also a bit of a messy one
      branch_results =
        Enum.map(clauses_list, fn {:->, _clause_meta, [[p_ast], e_ast]} ->
          case tc_pattern(module, p_ast, type_A, env_after_scrutinee) do
            {:ok, _bindings, env_for_e} ->
              tc_expr(module, env_for_e, st_pre, e_ast)
              |> case do
                # Success for this branch, return the result pair
                # todo: the names for these vars suck
                {:ok, {type_Ti, st_Q_i}, _env_final_i} -> {:ok, {type_Ti, st_Q_i}}
                # Error in branch body
                {:error, msg, _env} -> {:error, msg}
              end

            {:error, msg, _env} ->
              # Pattern didn't match type A
              {:error, msg}
          end
        end)

      # check if any branch failed
      if Enum.any?(branch_results, fn r -> match?({:error, _}, r) end) do
        {:error, first_error_msg} = Enum.find(branch_results, fn r -> match?({:error, _}, r) end)
        {:error, first_error_msg, env_after_scrutinee}
      else
        successful_results = Enum.map(branch_results, fn {:ok, res} -> res end)

        case Helpers.join_branch_results(successful_results) do
          {:ok, {final_T, final_Q2}} ->
            {:ok, {final_T, final_Q2}, env_after_scrutinee}

          {:error, [t1: _b1, t2: _b2] = error_branches} ->
            error_msg =
              Error.TypeMismatch.case_branches_incompatible_types(module, meta, error_branches)

            {:error, error_msg, env_after_scrutinee}

          {:error, [q1: _b1, q2: _b2] = error_branches} ->
            error_msg =
              Error.TypeMismatch.case_branches_incompatible_session_states(
                module,
                meta,
                error_branches
              )

            {:error, error_msg, env_after_scrutinee}
        end
      end
    else
      {:scrutinee, {:error, msg, env}} -> {:error, msg, env}
      {:error, msg} -> {:error, msg, var_env}
    end
  end

  # --- Maty Send Operation (T-Send) ---
  # Matches call to Maty.DSL.internal_send/3 which the send/2 macro expands to
  def tc_expr(
        module,
        var_env,
        st_pre,
        {{:., meta, [Maty.DSL, :internal_send]}, _, [_session_ctx, recipient_ast, message_ast]}
      ) do
    stack_trace(20)

    case st_pre do
      %ST.SOut{to: expected_role, branches: branches} ->
        with {:recipient, {:ok, {:atom, recipient_st}, recipient_env}} <-
               {:recipient, tc_expr(module, var_env, st_pre, recipient_ast)},
             # Ensure recipient check pure
             :ok <- Helpers.check_st_unchanged(st_pre, recipient_st, meta),

             # Check recipient matches expected rol
             {:role, [got: ^expected_role, expected: _expected_role], _st} <-
               {:role, [got: recipient_ast, expected: expected_role], recipient_st},

             # 4. Check message structure {label, payload_expr}
             #  pin - standardise helper function APIs
             {:message_ok, literal_label, payload_expr_ast} <-
               Helpers.check_message_structure(module, meta, message_ast),

             # Typecheck payload expression
             {:payload, {:ok, {actual_payload_type, payload_st}, payload_env}} <-
               {:payload, tc_expr(module, recipient_env, recipient_st, payload_expr_ast)},

             # 5. Find matching branch for the label
             #  pin - this is really messy
             {:branch, {:ok, matched_branch}, [got: _attempted_match, expected: _branches], _st} <-
               {
                 :branch,
                 Helpers.find_matching_branch(branches, {literal_label, actual_payload_type}),
                 [got: {literal_label, actual_payload_type}, expected: branches],
                 payload_st
               },
             %{payload: expected_payload_type, continue_as: st_Sj} = matched_branch,
             # Ensure payload check pure
             :ok <- Helpers.check_st_unchanged(recipient_st, payload_st, meta),
             # Check payload type matches expected
             # todo: should try have it so that the shape of the data sent to the error branches is a little more standardised / uniform
             {:payload, :ok, _st} <-
               {:payload, Helpers.check_payload_type(actual_payload_type, expected_payload_type),
                payload_st} do
          # All checks passed!
          # Result type is :atom, next session state is st_Sj
          # Use env after payload check
          {:ok, {:atom, st_Sj}, payload_env}
        else
          {:error, msg, env} ->
            {:error, msg, env}

          {:error, msg} ->
            {:error, msg, var_env}

          {:branch, {:error, :label_mismatch}, [got: {label_received, _}, expected: branches], st} ->
            branch_options = branches |> Enum.map(fn b -> b.label end)

            error_msg =
              Error.ProtocolViolation.incorrect_message_label(module, meta, st,
                got: label_received,
                expected: branch_options
              )

            {:error, error_msg, var_env}

          # todo: try doing something about this situation. don't wanna have to check twice for the label violations
          {:branch, {:error, :payload_mismatch},
           [got: {label_received, payload_received}, expected: branches], st} ->
            expected_branch =
              branches
              |> Enum.find(fn b -> b.label == label_received end)

            case expected_branch do
              nil ->
                branch_options = branches |> Enum.map(fn b -> b.label end)

                error_msg =
                  Error.ProtocolViolation.incorrect_message_label(
                    module,
                    meta,
                    st,
                    got: label_received,
                    expected: branch_options
                  )

                {:error, error_msg, var_env}

              other ->
                error_msg =
                  Error.ProtocolViolation.incorrect_payload_type(
                    module,
                    meta,
                    st,
                    got: payload_received,
                    expected: other.payload
                  )

                {:error, error_msg, var_env}
            end

          {:role, roles, st} ->
            error_msg =
              Error.ProtocolViolation.incorrect_target_participant(module, meta, st, roles)

            {:error, error_msg, var_env}

          {:payload, payloads, st} ->
            error_msg =
              Error.ProtocolViolation.incorrect_payload_type(module, meta, st, payloads)

            {:error, error_msg, var_env}

          # todo: fix this it
          {label, e} when label in [:recipient, :message, :branch, :payload] ->
            e
        end

      other_state ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            module,
            meta,
            # todo: try to render shape of message
            [got: "MatyDSL.send(:#{recipient_ast}, message)"],
            other_state
          )

        {:error, error_msg, var_env}
    end
  end

  # --- Maty setState (T-Set) ---
  def tc_expr(
        module,
        var_env,
        st_pre,
        {{:., meta, [Maty.DSL.State, :set]}, _, [state_ast, _new_state, _session_ctx]}
      ) do
    stack_trace(221)

    with :ok,
         # check that state_ast is state var
         {state_var, _, _} <- state_ast,
         {:v, {:ok, {state_type, ^st_pre}, var_env}} <-
           {:v, tc_expr(module, var_env, st_pre, state_ast)},
         :ok <- Helpers.check_maty_state_type(state_type),
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()) do
      {:ok, {Type.maty_actor_state(), st_pre}, var_env}
    else
      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(module, meta, error_internal)
        {:error, error_msg}

      # todo: revisit
      _other ->
        {:error, "set state operation is not well structured"}
    end
  end

  # --- Maty getState (T-Get) ---
  def tc_expr(
        module,
        var_env,
        st_pre,
        {{:., meta, [Maty.DSL.State, :get]}, _, [state_ast, _session_ctx]}
      ) do
    stack_trace(222)

    with :ok,
         # check that state_ast is state var
         {state_var, _, _} <- state_ast,
         {:v, {:ok, {state_type, ^st_pre}, var_env}} <-
           {:v, tc_expr(module, var_env, st_pre, state_ast)},
         :ok <- Helpers.check_maty_state_type(state_type),
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()) do
      {:ok, {:map, st_pre}, var_env}
    else
      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(module, meta, error_internal)
        {:error, error_msg}

      # todo: revisit
      _other ->
        {:error, "get state operation is not well structured"}
    end
  end

  # --- Maty Suspend Operation (T-Suspend) ---
  # Matches throw({:suspend, handler, state}) from Maty.DSL.suspend/2
  def tc_expr(
        module,
        var_env,
        st_pre,
        {{:., _, [:erlang, :throw]}, _, [{:{}, meta, [:suspend, handler_ast, state_ast]}]}
      ) do
    stack_trace(21)
    # todo: threading of environment and st in with clause
    with {:h, {:ok, {handler_type, h_st}, h_env}} <-
           {:h, tc_expr(module, var_env, st_pre, handler_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(st_pre, h_st, meta),
         # pin - maybe helper could return more standard type
         {:suspension, :ok, [got: _], _st} <-
           {:suspension, Helpers.check_handler_type(handler_type, meta), [got: handler_ast],
            st_pre},
         #
         {:v, {:ok, {state_type, v_st}, v_env}} <- {:v, tc_expr(module, h_env, h_st, state_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(h_st, v_st, meta),
         :ok <- Helpers.check_maty_state_type(state_type),
         {state_var, _, _} = state_ast,
         {:st, %ST.SName{handler: expected_handler}, _state_var} <- {:st, v_st, state_var},
         {:handler_name, [got: ^expected_handler, expected: _expected_handler], _st} <-
           {:handler_name, [got: handler_ast, expected: expected_handler], v_st} do
      {:ok, {:no_return, {:st_bottom, :suspend}}, v_env}
    else
      {:error, msg, env} ->
        {:error, msg, env}

      {:error, msg} ->
        {:error, msg, var_env}

      {:st, other_st, state_var} ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            module,
            meta,
            [got: "MatyDSL.suspend(:#{handler_ast}, #{state_var})"],
            other_st
          )

        {:error, error_msg, var_env}

      {:suspension, :error, [got: got], st} ->
        error_msg =
          Error.ProtocolViolation.suspend_invalid_handler_type(module, meta, [got: got], st)

        {:error, error_msg, var_env}

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(module, meta, error_internal)
        {:error, error_msg}

      {:handler_name, handlers, st} ->
        error_msg =
          Error.ProtocolViolation.incorrect_handler_suspension(module, meta, st, handlers)

        {:error, error_msg, var_env}
    end
  end

  # --- Maty Done Operation (T-Done) ---
  # Matches throw({:done, state}) from Maty.DSL.done/1
  # AST: {:throw, meta, [{:done, state_ast}]}

  def tc_expr(module, var_env, st_pre, {{:., _, [:erlang, :throw]}, meta, [done: state_ast]}) do
    stack_trace(22)

    with {:v, {:ok, {state_type, v_st}, v_env}} <-
           {:v, tc_expr(module, var_env, st_pre, state_ast)},
         # pin - maybe helper could return more standard type
         :ok <- Helpers.check_st_unchanged(st_pre, v_st, meta),
         :ok <- Helpers.check_maty_state_type(state_type),
         {state_var, _, _} = state_ast,
         {:st, %ST.SEnd{}, _state_var} <- {:st, v_st, state_var} do
      {:ok, {:no_return, {:st_bottom, :done}}, v_env}
    else
      {:error, msg, env} ->
        {:error, msg, env}

      {:error, msg} ->
        {:error, msg, var_env}

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(module, meta, error_internal)
        {:error, error_msg}

      {:st, other_st, state_var} ->
        error_msg =
          Error.ProtocolViolation.incorrect_action(
            module,
            meta,
            [got: "MatyDSL.done(#{state_var})"],
            other_st
          )

        {:error, error_msg, var_env}
    end
  end

  # --- Maty Register Operation (T-Register) V2 ---
  def tc_expr(
        module,
        var_env,
        st_pre,
        {{:., _m1, [Maty.DSL, :register]}, meta, [ap_pid_ast, role_ast, reg_info_ast, state_ast]}
      ) do
    stack_trace(22)

    with :ok,
         # is ap_pid_ast a PID?
         {:ap, {:ok, {:pid, ^st_pre}, _}} <- {:ap, tc_expr(module, var_env, st_pre, ap_pid_ast)},

         # is role_ast a role?
         {:role, {:ok, {:atom, ^st_pre}, _}} <-
           {:role, tc_expr(module, var_env, st_pre, role_ast)},

         # is init_handler a proper handler?
         # have they provided the required args?
         {:handler, {:ok, {{:fun, _arity}, st_pre}, var_env}} <-
           {:handler, tc_expr(module, var_env, st_pre, reg_info_ast)},

         # is state_ast an ActorState
         {:state, {:ok, {state_type, ^st_pre}, _}} <-
           {:state, tc_expr(module, var_env, st_pre, state_ast)},
         :ok <- Helpers.check_maty_state_type(state_type),
         return_type = {:tuple, [:ok, Type.maty_actor_state()]} do
      # all checks passed

      {:ok, {return_type, st_pre}, var_env}
    else
      {:ap, {:error, _msg, _var_env} = error} ->
        error

      {:role, {:error, _msg, _var_env} = error} ->
        error

      {:handler, {:error, _msg, _var_env} = error} ->
        error

      {:state, {:error, _msg, _var_env} = error} ->
        error

      {:maty_state_error, error_internal} ->
        error_msg = Error.TypeMismatch.invalid_maty_state_type(module, meta, error_internal)
        {:error, error_msg}

      other ->
        # pin - convert to new kind of error
        {:error, Error.internal_error("Unexpected mismatch in register check: #{inspect(other)}"),
         var_env}
    end
  end

  # --- Function Application (T-App) ---
  # Handles local function calls: f(arg1, arg2, ...)
  def tc_expr(module, var_env, st_pre, {func_name, meta, arg_asts} = ast)
      when is_atom(func_name) and is_list(arg_asts) and meta != [] and
             func_name not in [:=, :%, :{}, :|, :<<>>] do
    stack_trace(10)

    arity = length(arg_asts)
    func_id = {func_name, arity}

    psi = Utils.Env.get_map(module, :psi)

    # todo: maybe make use of more helpers?
    # get all the type signatures
    with {:ok, signatures} when is_list(signatures) and signatures != [] <-
           Map.fetch(psi, func_id) do
      # go through each list of arguments
      Enum.reduce_while(
        arg_asts,
        {:ok, {[], st_pre}, var_env},
        fn arg_ast, {:ok, {acc_arg_types, current_st}, current_env} ->
          case tc_expr(module, current_env, current_st, arg_ast) do
            {:ok, {actual_type, next_st}, next_env} ->
              # Accumulate actual types and pass state/env forward
              # session type should remain unchanged from typechecking the individual arguments
              # but we thread it through anyway
              {:cont, {:ok, {[actual_type | acc_arg_types], next_st}, next_env}}

            {:error, error, err_env} ->
              # Halt on first argument error
              {:halt, {:error, error, err_env}}
          end
        end
      )
      # if we make it here it means we were able to typecheck all asts
      |> case do
        {:ok, {actual_arg_types_rev, final_st}, final_env} ->
          actual_arg_types = Enum.reverse(actual_arg_types_rev)

          # match on the first matching signature
          Enum.find(signatures, fn {param_types, _return_type} ->
            # Check type compatibility for this signature
            compatible? =
              actual_arg_types
              |> Enum.zip(param_types)
              |> Enum.all?(fn {got, expected} -> got == expected end)

            # Check arity
            compatible? and length(actual_arg_types) == length(param_types)
          end)
          |> case do
            {_param_types, return_type} ->
              # match exists
              {:ok, {return_type, final_st}, final_env}

            nil ->
              # match does not exist
              Logger.error(inspect(ast))

              error =
                Error.FunctionCall.no_matching_function_clause(
                  module,
                  meta,
                  func_id,
                  actual_arg_types
                )

              {:error, error, final_env}
          end

        {:error, error, final_env} ->
          # An error occurred during argument typechecking
          {:error, error, final_env}
      end
    else
      {:ok, []} ->
        error = Error.FunctionCall.function_not_exist(module, meta, func_id)
        {:error, error, var_env}

      :error ->
        error = Error.FunctionCall.function_not_exist(module, meta, func_id)
        {:error, error, var_env}
    end
  end

  # Variable Lookup (TV-Var adaptation)
  # Looking up a variable is pure; preserves session state.
  def tc_expr(_module, var_env, st_pre, {var_name, meta, context})
      when is_atom(var_name) and (is_nil(context) or is_list(context)) do
    stack_trace(25)

    # Logger.info(inspect(ast), ansi_color: :yellow)

    case Map.fetch(var_env, var_name) do
      {:ok, elixir_type} -> {:ok, {elixir_type, st_pre}, var_env}
      # pin - convert to new kind of error
      :error -> {:error, Error.variable_not_exist(meta, var_name), var_env}
    end
  end

  # Clause for TV-MsgHandler, TV-InitHandler (Handler names as values)
  # These need access to the Delta environment. Preserves session state.
  # --- Simplified Handler Name / Atom Logic ---
  # Assumes variable shadowing doesn't occur for handler names.

  # This clause handles atoms that might be handler names.
  def tc_expr(module, var_env, st_pre, value)
      when is_atom(value) and not is_nil(value) do
    stack_trace(23)
    # Check Delta environments directly
    delta_M = Utils.Env.get_map(module, :delta_M)
    delta_I = Utils.Env.get_map(module, :delta_I)

    cond do
      Map.has_key?(delta_M, value) ->
        {:ok, {:maty_handler_msg, st_pre}, var_env}

      Map.has_key?(delta_I, value) ->
        {:ok, {:maty_handler_init, st_pre}, var_env}

      true ->
        # Not a handler name, treat as a standard atom literal.
        # Fall through by calling the more general atom clause.
        stack_trace(203)

        # Logger.debug(
        #   "Already checked if #{value} is a variable or handler so it could only be an atom?",
        #   ansi_color: :magenta
        # )

        {:ok, {:atom, st_pre}, var_env}
    end
  end

  # General Atom Literal Clause (catches atoms not matched above)
  def tc_expr(_module, var_env, st_pre, value) when is_atom(value) and not is_nil(value) do
    stack_trace(24)
    # Logger.debug("This: #{inspect(value)} is an atom", ansi_color: :magenta)

    {:ok, {:atom, st_pre}, var_env}
  end

  @doc """
  Checks if a function definition is well-formed according to WF-Func.
  Verifies argument patterns, body type, return type, and session state purity.

  Returns `{:ok, return_type}` or `{:error, message}` for each function clause checked.
  """
  @spec check_wf_function(
          module :: module(),
          func_id :: {atom(), non_neg_integer()},
          clauses :: [Macro.t()]
        ) ::
          [{:ok, Type.t()} | {:error, binary()}]
  def check_wf_function(module, {_name, arity} = func_id, clauses) do
    psi = Utils.Env.get_map(module, :psi)

    case Map.fetch(psi, func_id) do
      {:ok, signatures} when is_list(signatures) ->
        defs = Enum.zip(signatures, clauses)

        for {{spec_args_types, spec_return_type},
             {clause_meta, arg_pattern_asts, _guards, body_block}} <- defs do
          with :arity_ok <-
                 Helpers.check_clause_arity(module, clause_meta, func_id, arity, spec_args_types),
               # pin - maybe helper could return more standard type
               {:args_ok, body_var_env} <-
                 Helpers.check_argument_patterns(
                   module,
                   clause_meta,
                   arg_pattern_asts,
                   spec_args_types
                 ),
               # pin - maybe helper could return more standard type
               {:body_ok, {actual_return_type, final_st}, _final_env} <-
                 check_function_body(module, body_var_env, body_block),
               # pin - maybe helper could return more standard type
               :state_ok <-
                 Helpers.check_final_session_state(module, clause_meta, func_id, final_st),
               :type_ok <-
                 Helpers.check_return_type(
                   module,
                   clause_meta,
                   actual_return_type,
                   spec_return_type
                 ) do
            {:ok, actual_return_type}
          else
            {:error, error_msg} -> {:error, error_msg}
          end
        end

      :error ->
        error = Error.TypeSpecification.no_spec_for_function(module, func_id)
        List.duplicate({:error, error}, length(clauses))
    end
  end

  @doc """
  Checks a single message handler clause based on WF-MsgHandler.

  Verifies the declared role/label/payload pattern against the session type
  associated with the handler_label, and checks if the body correctly
  implements the session continuation, ending in done/suspend.

  Returns `{:ok, {label, role}}` if well-formed, identifying the session
  branch handled. Otherwise returns `{:error, message}`.
  """
  @spec check_wf_message_handler_clause(
          module :: module(),
          handler_label :: atom(),
          handler_ast_clause :: Macro.t(),
          st_pre :: ST.t(),
          type_signature :: tuple()
        ) :: {:ok, ST.SBranch.t()} | {:error, binary()}
  def check_wf_message_handler_clause(
        module,
        handler_label,
        {clause_meta, args, _guards, body_block},
        st_pre,
        type_signature
      ) do
    with [received_role, message_pattern_ast, state_var_ast, _session_ctx_var_ast] <- args,
         {[declared_role, message_type, _state, _session_ctx], _return_type} <- type_signature,

         # get name of state variable
         {state_var, _, _} <- state_var_ast,

         # role should already just be an atom
         {:ok, {:atom, ^st_pre}, _} <- tc_expr(module, %{}, st_pre, received_role),

         # get shape of message
         # bind whatever from the message payload
         {:ok, _message_bindings, var_env} <-
           tc_pattern(module, message_pattern_ast, message_type, %{}),

         # create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         # need to also add psi here
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         #  var_env = Map.merge(gamma_args_env, psi),
         # check the session type is SIn
         {:st, st = %ST.SIn{from: expected_role, branches: branches}} <- {:st, st_pre},

         # check handler and session type roles align
         {:role, [got: ^expected_role, expected: _expected_role], _st} <-
           {:role, [got: ^received_role = declared_role, expected: expected_role], st},
         {label, _} <- message_pattern_ast,
         {:tuple, [_, payload_type]} <- message_type,

         # check there is a matching branch
         # take note of this branch
         {:branch, {:ok, handler_branch}, [got: _attempted_match, expected: _branches], _st} <-
           {:branch,
            Helpers.find_matching_branch(
              branches,
              {label, payload_type}
            ), [got: {label, payload_type}, expected: branches], st},

         # extract only the relevant bits (leave out the try catch)
         body = extract_body(body_block),
         {:ok, {:no_return, {:st_bottom, _exit_status}}, _var_env} <-
           tc_expr_list(module, var_env, handler_branch.continue_as, body) do
      # all checks passed!
      {:ok, handler_branch}
    else
      {:error, msg, _env} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}

      {:st, other_st} ->
        {:error, "st broken: #{inspect(other_st)}"}

      {:role, [got: role_received, expected: role_expected], st} ->
        error_msg =
          Error.ProtocolViolation.incorrect_recipient_participant(
            module,
            handler_label,
            st,
            got: role_received,
            expected: role_expected
          )

        {:error, error_msg}

      {:branch, {:error, :label_mismatch},
       [got: {label_received, _payload_received}, expected: branches], st} ->
        branch_options = branches |> Enum.map(fn b -> b.label end)

        error_msg =
          Error.ProtocolViolation.incorrect_incoming_message_label(module, handler_label, st,
            got: label_received,
            expected: branch_options
          )

        {:error, error_msg}

      # todo: fix the double incorrect message label check
      {:branch, {:error, :payload_mismatch},
       [got: {label_received, payload_received}, expected: branches], st} ->
        expected_branch =
          branches
          |> Enum.find(fn b -> b.label == label_received end)

        case expected_branch do
          nil ->
            branch_options = branches |> Enum.map(fn b -> b.label end)

            error_msg =
              Error.ProtocolViolation.incorrect_incoming_message_label(
                module,
                handler_label,
                st,
                got: label_received,
                expected: branch_options
              )

            {:error, error_msg}

          other ->
            error_msg =
              Error.ProtocolViolation.incorrect_incoming_payload_type(module, handler_label, st,
                got: payload_received,
                expected: other.payload
              )

            {:error, error_msg}
        end

      {:body_ok, {final_type, final_state}, _env} ->
        error =
          Error.handler_body_wrong_termination(
            clause_meta,
            handler_label,
            final_type,
            final_state
          )

        {:error, error}

      other ->
        # pin - convert to new kind of error
        {:error, Error.internal_error("Unexpected mismatch in handler check: #{inspect(other)}")}
    end
  end

  @doc """
  Checks a single initialisation handler clause based on WF-InitHandler.

  Verifies the declared argument pattern against the spec type, and checks
  if the body correctly implements the initial session state, ending in
  done/suspend.

  Returns `{:ok, handler_label}` if well-formed. Otherwise returns `{:error, message}`.
  """

  # [
  #   {_meta, [args_ast, state_var_ast, session_ctx], [],
  #    {:try, _, [[do: {:__block__, _, [_, _, {:__block__, _, block}]}, catch: _]]}}
  # ]

  @spec check_wf_init_handler_clause(
          module :: module(),
          handler_label :: atom(),
          handler_ast_clause :: Macro.t(),
          st_pre :: ST.t(),
          type_signature :: tuple()
        ) ::
          :ok | {:error, binary()}
  def check_wf_init_handler_clause(
        module,
        handler_label,
        {clause_meta, args, _guards, body_block},
        st_pre,
        type_signature
      ) do
    with [arg_pattern_ast, state_var_ast, _session_ctx_var_ast] <- args,
         {[args_types, _state, _session_ctx], _return_type} <- type_signature,
         #  get name of state variable
         {state_var, _, _} <- state_var_ast,

         #  bind whatever from the args
         {:ok, _message_bindings, var_env} <-
           tc_pattern(module, arg_pattern_ast, args_types, %{}),

         #  create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         # check the session type is NOT SIn (should be SOut or Suspend)
         {:st, :ok} <- {:st, Helpers.check_init_st(st_pre)},

         # extract only the relevant bits (leave out the try catch)
         body = extract_body(body_block),
         {:ok, {:no_return, {:st_bottom, _exit_status}}, _var_env} <-
           tc_expr_list(module, var_env, st_pre, body) do
      # all checks passed!
      :ok
    else
      {:error, msg, _env} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}

      {:body_ok, {final_type, final_state}, _env} ->
        error =
          Error.handler_body_wrong_termination(
            clause_meta,
            handler_label,
            final_type,
            final_state
          )

        {:error, error}

      {:st, {:error, _msg} = error} ->
        error

      other ->
        # pin - convert to new kind of error
        error_msg =
          Error.internal_error("Unexpected mismatch in init handler check: #{inspect(other)}")

        {:error, error_msg}
    end
  end

  def check_wf_on_link_callback(
        module,
        {_clause_meta, args, _guards, body_block},
        type_signature
      ) do
    with [arg_pattern_ast, state_var_ast] <- args,
         {[args_types, _state], _return_type} <- type_signature,

         #  get name of state variable
         {state_var, _, _} <- state_var_ast,

         # bind variables from the function signature
         {:ok, _message_bindings, var_env} <-
           tc_pattern(module, arg_pattern_ast, args_types, %{}),
         #  create all the necessary bindings (this thing Γ_args, x : ActorState(B))
         var_env = Map.put(var_env, state_var, Type.maty_actor_state()),

         # typecheck the function (calls to register etc.)
         body = extract_body(body_block),
         {:ok, {return_type, %ST.SEnd{}}, _var_env} <-
           tc_expr_list(module, var_env, %ST.SEnd{}, body),

         # make sure there is at least one call to register in this function
         {:register, true} <- {:register, Helpers.contains_register_call?(body)},

         # make sure the function returns {:ok, some_actor_state}
         true <- return_type == {:tuple, [:ok, Type.maty_actor_state()]} do
      # all checks pass
      :ok
    else
      {:error, msg, _var_env} -> {:error, msg}
      # pin - convert to new kind of error
      other -> {:error, "Something is not looking right: #{inspect(other)}"}
    end
  end

  # move
  # Processes a list of expressions sequentially using tc_expr.
  # Returns the result of the *last* expression in the list.
  @spec tc_expr_list(
          module :: module(),
          var_env :: var_env(),
          st_pre :: ST.t(),
          ast_list :: [ast()]
        ) ::
          {:ok, {Type.t(), ST.t()}, var_env()} | {:error, binary(), var_env()}
  def tc_expr_list(_module, var_env, st_pre, []) do
    # Result of an empty block is nil, state preserved.
    {:ok, {nil, st_pre}, var_env}
  end

  def tc_expr_list(module, var_env, st_pre, ast_list) do
    # Reduce over expressions, threading state and env. Keep track of the *last* result.

    Enum.reduce_while(
      ast_list,
      {:ok, {nil, st_pre}, var_env},
      fn expr_ast, {:ok, {_prev_result, current_st}, current_env} ->
        # Logger.info("AST: #{inspect(expr_ast)}")

        case tc_expr(module, current_env, current_st, expr_ast) do
          {:ok, last_result, next_env} ->
            # Store the latest successful result and continue
            # Logger.error("last item in block: #{inspect(last_result)}")
            {:cont, {:ok, last_result, next_env}}

          {:error, error, err_env} ->
            # Halt on first error
            {:halt, {:error, error, err_env}}
        end
      end
    )
  end

  # move
  # check if argument alters session state
  defp check_function_body(module, body_var_env, body_block) do
    body_asts = extract_body(body_block)
    initial_st = %ST.SEnd{}

    case tc_expr_list(module, body_var_env, initial_st, body_asts) do
      {:ok, {return_type, final_st}, final_env} ->
        {:body_ok, {return_type, final_st}, final_env}

      {:error, msg, _env} ->
        {:error, msg}
    end
  end

  # move ?
  # Extracts a list of expressions from an AST body.
  #
  # This handles both block expressions (`do: begin ... end`) and single expressions.
  #
  # Returns:
  #   - A list of expressions representing the body
  @spec extract_body(Macro.t()) :: [Macro.t()]

  defp extract_body({:__block__, _, block}), do: block

  defp extract_body({:try, _, [[do: {:__block__, _, [_, _, body_block]}, catch: _]]}),
    do: extract_body(body_block)

  defp extract_body(expr) when not is_list(expr), do: [expr]
end
