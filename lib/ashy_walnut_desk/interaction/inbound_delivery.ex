defmodule AshyWalnutDesk.Interaction.InboundDelivery do
  @moduledoc """
  Dedupe ledger for inbound webhook deliveries (story 3.4, ADR-024
  C1). Immutable: no soft-delete, no destroy from operator paths.
  Daily `:expunge_expired` AshOban trigger removes rows older than
  the retention window.

  Unique index on `(provider, provider_message_id)` is the source of
  truth for "already processed." A Twilio retry with the same
  `MessageSid` hits the constraint and we return 200 OK without
  re-creating chain rows.

  See `specs/phase-3/architecture.md §3.1`.
  """

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban],
    primary_read_warning?: false

  alias AshyWalnutDesk.Interaction.Checks.FromInboundWebhook

  @retention_days 7

  postgres do
    table("inbound_deliveries")
    repo(AshyWalnutDesk.Repo)

    custom_indexes do
      index([:provider, :provider_message_id], unique: true)
      index([:received_at])
    end
  end

  oban do
    triggers do
      trigger :expunge_expired do
        action(:expunge_expired)
        read_action(:expired)
        scheduler_cron("0 4 * * *")
        where(expr(received_at < ago(^@retention_days, :day)))
        worker_module_name(__MODULE__.AshOban.Worker.ExpungeExpired)
        scheduler_module_name(__MODULE__.AshOban.Scheduler.ExpungeExpired)
        queue(:default)
      end
    end
  end

  actions do
    default_accept([])
    defaults([:read])

    read :expired do
      pagination(keyset?: true, required?: false)
      filter(expr(received_at < ago(^@retention_days, :day)))
    end

    create :record_delivery do
      accept([:provider, :provider_message_id, :outcome, :intake_failure_reason])
      change(set_attribute(:received_at, &DateTime.utc_now/0))
    end

    destroy :expunge_expired do
      change(filter(expr(received_at < ago(^@retention_days, :day))))
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    # Internal-only: webhook controller writes via FromInboundWebhook
    # context; admin gets a read-only view for operational debugging.
    policy action(:record_delivery) do
      authorize_if(FromInboundWebhook)
    end
  end

  field_policies do
    field_policy :provider_message_id do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :provider, :atom do
      allow_nil?(false)
      constraints(one_of: [:twilio, :stub, :echo])
      public?(true)
    end

    attribute :provider_message_id, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :received_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute :outcome, :atom do
      allow_nil?(false)
      constraints(one_of: [:processed, :duplicate, :failed_intake])
      public?(true)
    end

    attribute :intake_failure_reason, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
  end

  def retention_days, do: @retention_days
end
