defmodule AshyWalnutDesk.Interaction.Draft do
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

  alias AshyWalnutDesk.Interaction.Changes.{
    AppendDisclosureFooter,
    ChainLink,
    CompensationAtApproval,
    EnqueueGenerationWorker,
    StampModelFromPersona,
    SupersedeSiblingDraftCandidates
  }

  alias AshyWalnutDesk.Interaction.Checks.FromGenerationWorker
  alias AshyWalnutDesk.Interaction.Validations.StatusTransition
  alias AshyWalnutDesk.Interaction.Validations.ValidatorPassed

  postgres do
    table("drafts")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:inbox, on_delete: :restrict)
      reference(:approved_by, on_delete: :restrict)
      reference(:persona, on_delete: :restrict)
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

    create :compose_draft do
      accept([
        :inbox_id,
        :body,
        :compensation_body,
        :status,
        :ai_prompt,
        :ai_model,
        :ai_response,
        :ai_validator_output
      ])

      change({ChainLink, event_type: :draft_started})
    end

    create :generate do
      accept([:inbox_id, :persona_id])
      change(set_attribute(:status, :generating))
      change(set_attribute(:body, ""))
      change(StampModelFromPersona)
      change(EnqueueGenerationWorker)
      change({ChainLink, event_type: :draft_generation_requested})
    end

    # C2: per-transition status changes go through named actions
    # (`:reject`, `:supersede`, `:approve`). `:revise` only edits
    # body/compensation/AI metadata — no `:status` in the accept
    # list, no chance of an operator backing into `:approved` via
    # free-form attribute update.
    update :revise do
      accept([
        :body,
        :compensation_body,
        :ai_prompt,
        :ai_model,
        :ai_response,
        :ai_validator_output
      ])

      require_atomic?(false)
      validate({StatusTransition, from: [:drafting]})
    end

    update :reject do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:drafting]})
      change(set_attribute(:status, :rejected))
    end

    update :supersede do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:drafting]})
      change(set_attribute(:status, :superseded))
      change({ChainLink, event_type: :draft_superseded})
    end

    update :approve do
      accept([:compensation_body])
      require_atomic?(false)
      validate(ValidatorPassed)
      change(CompensationAtApproval)
      change(set_attribute(:status, :approved))
      change(set_attribute(:approved_at, &DateTime.utc_now/0))
      change(relate_actor(:approved_by))
      change(SupersedeSiblingDraftCandidates)
      change({ChainLink, event_type: :draft_approved})
    end

    # Completes a generation REGARDLESS of validator outcome (architecture
    # §8.2): a validator-failed draft persists to :drafting as a reviewable
    # candidate with its violations in ai_validator_output — it is NOT
    # auto-rejected. The :approve action's ValidatorPassed gate (below) is
    # what blocks a failed draft from being sent, so the operator can see
    # why it failed and revise/regenerate/reject. Only provider failures
    # (:permanent/:content_blocked) route to :fail_generation → :rejected.
    update :complete_generation do
      accept([:body, :ai_prompt, :ai_model, :ai_response, :ai_validator_output, :ai_retrieval])
      require_atomic?(false)
      validate({StatusTransition, from: [:generating]})
      change(AppendDisclosureFooter)
      change(set_attribute(:status, :drafting))
      change({ChainLink, event_type: :draft_generation_completed})
    end

    update :fail_generation do
      accept([:ai_validator_output, :ai_retrieval])
      require_atomic?(false)
      validate({StatusTransition, from: [:generating]})
      change(set_attribute(:status, :rejected))
      change({ChainLink, event_type: :draft_generation_failed})
    end

    # Test-only escape hatch: backdate `approved_at` so countdown tests
    # can simulate the 5-second window having elapsed without sleeping.
    # The `forbid_if always()` policy means production callers cannot
    # invoke this — only test fixtures going through `authorize?: false`
    # can. See the AGENTS.md gotcha about fixture actions.
    update :backdate_approval_for_tests do
      accept([:approved_at])
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

    policy action(:compose_draft) do
      authorize_if(AdminOrOperator)
    end

    policy action(:revise) do
      authorize_if(AdminOrOperator)
    end

    policy action(:reject) do
      authorize_if(AdminOrOperator)
    end

    policy action(:supersede) do
      authorize_if(AdminOrOperator)
    end

    policy action(:approve) do
      authorize_if(AdminOrOperator)
    end

    policy action(:generate) do
      authorize_if(AdminOrOperator)
    end

    policy action(:complete_generation) do
      authorize_if(FromGenerationWorker)
    end

    policy action(:fail_generation) do
      authorize_if(FromGenerationWorker)
    end

    policy action(:backdate_approval_for_tests) do
      forbid_if(always())
    end

    policy action(:archive) do
      authorize_if(AdminOrOperator)
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  # Sec-fix R8: Draft.body and Draft.compensation_body carry the
  # outbound text drafted by an operator (and the matching
  # compensation message). Same posture as Message.body and
  # Compensation.body — admin/operator only; viewers see the
  # row's status / FKs but not the message text.
  field_policies do
    field_policy :body do
      authorize_if(AdminOrOperator)
    end

    field_policy :compensation_body do
      authorize_if(AdminOrOperator)
    end

    field_policy :ai_prompt do
      authorize_if(AdminOrOperator)
    end

    field_policy :ai_response do
      authorize_if(AdminOrOperator)
    end

    # Sec-fix R13: Phase 4 metadata. `:ai_model` is the model
    # identifier (e.g. "claude-opus-4.7"); not raw PII but reveals
    # deployment topology and could fingerprint deployers across
    # leaked tables. `:ai_validator_output` is a free-form map that
    # may carry validator flags + redacted prompt fragments — same
    # treatment as `:ai_response`. R12 gated the prompt/response;
    # this round closes the metadata pair.
    field_policy :ai_model do
      authorize_if(AdminOrOperator)
    end

    field_policy :ai_validator_output do
      authorize_if(AdminOrOperator)
    end

    field_policy :ai_retrieval do
      authorize_if(AdminOrOperator)
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    # Sec-fix R3: same upper bound as Message.body (the outbound
    # row mirrors this).
    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
      constraints(max_length: 2_000, allow_empty?: true)
    end

    attribute :compensation_body, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
      constraints(max_length: 2_000)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:generating, :drafting, :approved, :superseded, :rejected])
      public?(true)
    end

    attribute :approved_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :ai_prompt, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :ai_model, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :ai_response, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :ai_validator_output, :map do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    # Story 5.5: retrieval provenance — which Manual chunks (id/slug,
    # revision, position, content_hash, score, embedder) grounded the
    # generation, plus the retrieval mode. Excerpt TEXT is not
    # duplicated here; it persists verbatim inside ai_prompt.
    attribute :ai_retrieval, :map do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :deleted_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :inbox, AshyWalnutDesk.Interaction.Inbox do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :approved_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(true)
      # FK set exclusively via `change(relate_actor(:approved_by))` on
      # :approve. Non-writable so a future caller adding
      # `:approved_by_id` to an accept list cannot stamp the approver
      # field directly (countdown bypass).
      attribute_writable?(false)
      public?(true)
    end

    belongs_to :persona, AshyWalnutDesk.Knowledge.Persona do
      allow_nil?(true)
      public?(true)
    end
  end
end
