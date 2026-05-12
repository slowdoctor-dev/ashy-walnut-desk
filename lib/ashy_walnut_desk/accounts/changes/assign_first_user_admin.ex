defmodule AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdmin do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Accounts.User

  @retry_context_key :first_user_admin_retry

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      role =
        if Map.get(changeset.context, @retry_context_key, false) do
          :operator
        else
          choose_role()
        end

      Changeset.force_change_attribute(changeset, :role, role)
    end)
    |> Changeset.after_transaction(fn changeset, result ->
      maybe_retry_as_operator(changeset, result, context)
    end)
  end

  defp choose_role do
    case Ash.exists(User, authorize?: false) do
      {:ok, true} -> :operator
      {:ok, false} -> :admin
      {:error, _} -> :operator
    end
  end

  defp maybe_retry_as_operator(changeset, {:error, error}, context) do
    if admin_index_conflict?(error) and not Map.get(changeset.context, @retry_context_key, false) do
      opts =
        []
        |> maybe_put(:actor, context.actor)
        |> maybe_put(:tenant, context.tenant)
        |> maybe_put(:authorize?, Map.get(context, :authorize?, true))
        |> Keyword.put(:context, Map.put(changeset.context, @retry_context_key, true))

      changeset.resource
      |> Ash.Changeset.for_create(changeset.action.name, changeset.arguments, opts)
      |> Ash.create()
    else
      {:error, error}
    end
  end

  defp maybe_retry_as_operator(_changeset, result, _context), do: result

  defp admin_index_conflict?(error) do
    message = Exception.message(error)
    String.contains?(message, "users_one_admin_idx")
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
