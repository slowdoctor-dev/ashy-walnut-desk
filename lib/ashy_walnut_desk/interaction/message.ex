defmodule AshyWalnutDesk.Interaction.Message do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Accounts.Checks.AdminOrOperator
  alias AshyWalnutDesk.Identity.Changes.SoftDelete

  postgres do
    table("messages")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:conversation, on_delete: :restrict)
      reference(:approved_by, on_delete: :restrict)
    end
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    sensitive_attributes(:redact)
    version_extensions(authorizers: [Ash.Policy.Authorizer])
    mixin(AshyWalnutDesk.AdminOnlyVersions)
  end

  actions do
    default_accept([])

    read :read do
      primary?(true)
      filter(expr(is_nil(deleted_at)))
    end

    read :read_with_archived do
    end

    create :record_message do
      accept([
        :conversation_id,
        :direction,
        :body,
        :sent_at,
        :approved_by_id,
        :outbound_idempotency_key
      ])

      validate(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :direction) do
          :outbound ->
            # Story 3.fix: accept either context flag. Phase 2's
            # `from_action_execute` is the legacy name; story 3.5
            # introduced `from_action_worker` for the same semantic
            # ("internal send-path write"). Compensation worker path
            # (story 3.6) writes via the action-worker route, action
            # write goes through Changes.RecordOutbound which still
            # passes the legacy flag. Both must be honored until a
            # future cleanup pass standardizes on one.
            ctx = changeset.context

            if Map.get(ctx, :from_action_execute, false) or
                 Map.get(ctx, :from_action_worker, false) do
              :ok
            else
              {:error,
               field: :direction,
               message: "outbound messages must be created through the Action.execute path"}
            end

          :inbound ->
            # ADR-024: inbound rows are intake-only — they cannot
            # be created via an operator path. Webhook controller
            # passes `from_inbound_webhook: true`.
            if Map.get(changeset.context, :from_inbound_webhook, false) do
              :ok
            else
              {:error,
               field: :direction,
               message: "inbound messages must be created through the webhook intake path"}
            end

          _ ->
            :ok
        end
      end)
    end

    update :archive do
      accept([])
      require_atomic?(false)
      change(SoftDelete)
    end

    update :recover do
      accept([])
      require_atomic?(false)
      change(set_attribute(:deleted_at, nil))
    end
  end

  policies do
    policy action(:read) do
      authorize_if(AdminOrOperator)
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:record_message) do
      authorize_if(AdminOrOperator)
    end

    policy action(:archive) do
      authorize_if(AdminOrOperator)
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    field_policy :body do
      authorize_if(AdminOrOperator)
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :direction, :atom do
      allow_nil?(false)
      constraints(one_of: [:inbound, :outbound])
      public?(true)
    end

    # Sec-fix R3: bound the body size so a malformed inbound webhook
    # or a forged provider payload can't blob megabytes into the
    # database (and downstream into AuditEvent payloads / paper
    # trail). 2_000 chars comfortably exceeds Twilio's 1_600-char
    # SMS limit, with headroom for future providers (WhatsApp text
    # is 4_096 — deployers landing that adapter can override).
    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
      constraints(max_length: 2_000)
    end

    attribute :sent_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :deleted_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    # Story 3.5 / ADR-023. For outbound messages: carries the Action's
    # `outbound_idempotency_key` so the Twilio adapter can pass it as
    # the `Idempotency-Key` header. Stamped on the in-memory struct by
    # `Jobs.OutboundSend.build_outbound_message/2` *before* the adapter
    # call; persisted on the row by `Changes.RecordOutbound` after the
    # adapter accepts. Nil for inbound messages.
    attribute :outbound_idempotency_key, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :conversation, AshyWalnutDesk.Interaction.Conversation do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :approved_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(true)
      public?(true)
    end
  end
end
