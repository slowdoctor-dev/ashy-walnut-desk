defmodule AshyWalnutDesk.Accounts.User.VersionPolicies do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      policies do
        policy action_type(:read) do
          authorize_if(actor_attribute_equals(:role, :admin))
        end
      end
    end
  end
end
