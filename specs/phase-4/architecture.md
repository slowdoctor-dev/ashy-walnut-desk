# Phase 4 — Architecture

> Drafted by the BMAD Architect persona (Claude). Translates
> `specs/phase-4/requirements.md` into resource-level technical design
> + resolves Q1-Q8 from §7 as architectural decisions.

## 1. Overview

Phase 4 layers AI-assisted draft generation on top of the Phase 2
four-stage chain and Phase 3 real-channel substrate. Three new
subsystems join the codebase:

- **`AshyWalnutDesk.AI`** — provider-agnostic generation pipeline.
  `AI.Adapter` behaviour (Req-direct Anthropic real impl + test
  Fixture impl per ADR-025), `AI.PromptAssembler`, `AI.GenerationWorker`
  (Oban).
- **`AshyWalnutDesk.Safety`** — content gating. `Safety.Validator`
  behaviour, `Safety.Validators.Baseline` (framework rules), runtime
  `Safety.HonestFraming` check on AI-generated body text, and a
  composite chain that lets a deployment register additional
  validators via Application env.
- **`AshyWalnutDesk.Knowledge`** — minimum surface for prompt context.
  One Ash resource (`Knowledge.Persona`) holds the system prompt,
  AI-assistance disclosure text, optional model override, and
  guardrail notes. Full Knowledge-axis RAG (manuals, references,
  pgvector) is Phase 5; Phase 4 ships only Persona.

Generation is **operator-triggered only** (requirements §3 in-scope).
Auto-generate-on-inbound-arrival is explicitly out of scope and
deferred. Flow:

```text
                                                    ┌────────────────────────┐
                                                    │  Anthropic Messages API│
                                                    └──┬─────────────────▲───┘
                                                       │                 │
                                              POST     │                 │ JSON response
                                              with     │                 │ (content, usage,
                                              cache_   │                 │  stop_reason)
                                              control  │                 │
                                                       ▼                 │
                ┌──────────────────────────────────────────────────────┐ │
                │           AshyWalnutDesk.AI.Adapters                 │ │
                │                                                      │ │
                │   AI.Adapter (behaviour) ◄── Anthropic (real)        │ │
                │                          └── Fixture  (test-only)   │ │
                └──────────────────────────────────────────────────────┘ │
                          ▲                                              │
                          │ complete(prompt, opts)                       │
                          │                                              │
                ┌─────────┴────────────────────────────────────────────┐ │
                │       AshyWalnutDesk.AI.GenerationWorker (Oban)      │ │
                │                                                      │ │
                │   1. Load Draft + Inbox + Conversation context       │ │
                │   2. PromptAssembler.build/1                         │ │
                │   3. Adapter.complete/2                              │ │
                │   4. Safety.Validator.check/2                        │ │
                │   5. Persona.disclosure_text appended server-side    │ │
                │   6. Draft.:complete_generation OR :fail_generation  │ │
                │   7. Phoenix.PubSub broadcast → operator LV          │ │
                └──────────────────────────────────────────────────────┘
                          ▲
                          │ enqueued by
                          │
                ┌─────────┴────────────────────────────────────────────┐
                │   Draft.:generate (Ash action, operator/admin gated) │
                │                                                      │
                │   Creates a new Draft row in :generating status,     │
                │   enqueues GenerationWorker keyed on draft_id.       │
                │   Existing :drafting Drafts on the same Inbox are    │
                │   left alone (multi-candidate per §7 Q5).            │
                └──────────────────────────────────────────────────────┘
```

After `:complete_generation`, the chain re-enters the Phase 2/3 flow
unchanged: operator reviews → `Draft.:approve` (with new precondition:
validator passed) → 5-second countdown → `Action.:execute` → Oban
outbound worker → Twilio.

Multi-candidate semantics: regenerating creates **another** Draft on
the same Inbox; both stay visible in the candidate carousel. The
operator picks a winner via `Draft.:approve` (which auto-supersedes
the losers via a new `ChainLink` change) or via the existing
`Draft.:supersede`. Both losers and winner remain in the chain as
forensic record. Each generation, each validator outcome, and each
supersession is its own audit event.

Trade-offs (decision rationale lives in §11; this is the elevator
list):

- **Req-direct Anthropic over `ash_ai`** (ADR-025). Auditability +
  cache-control precision + test-fixture seam > the cost of carrying
  our own thin adapter.
- **Reuse Draft instead of a new `AI.Generation` resource.** The
  existing `ai_prompt / ai_model / ai_response / ai_validator_output`
  fields on Draft already field-policy-gated through Phase 3's sec
  rounds. Adding a sidecar table would split provenance across two
  rows and complicate the chain. Multi-candidate is just multiple
  Drafts on one Inbox — a shape the resource model already supports.
- **Oban worker over inline LV generation.** Anthropic round-trips
  are 1–8 seconds typical, 30+ for Opus at edge. LV process must not
  block. Oban survives BEAM restarts, retries idempotently on
  transient failures (same pattern Phase 3 established for outbound
  Twilio per ADR-023).
- **Persona as Ash resource, not config file.** Disclosure text and
  system prompt are deployer-configurable runtime content (per
  AGENTS.md §6 + §7.5). Resource gets paper-trail + admin-only
  policies; config file would bypass audit and force deploys for
  copy changes.
- **HonestFraming runtime check, not source-file scan.** The Phase 2
  `honest_framing_test.exs` is a source-file grep — it cannot see
  AI-generated body strings, which only exist at runtime. Phase 4
  ships a runtime `Safety.HonestFraming.check/1` that the Validator
  invokes on Anthropic output. The source-file test continues to
  guard template/gettext copy.

## 2. Affected modules

### New (AI domain)

```
lib/ashy_walnut_desk/ai/
├── ai.ex                          # Ash.Domain shell
├── adapter.ex                     # behaviour: complete/2
├── adapters/
│   ├── anthropic.ex               # real Req-direct Anthropic impl
│   └── fixture.ex                 # test-only deterministic impl
├── prompt_assembler.ex            # layered prompt with cache_control
├── prompt.ex                      # %AI.Prompt{} struct (blocks, model, max_tokens)
├── response.ex                    # %AI.Response{} struct (text, usage, stop_reason)
└── jobs/
    └── generation_worker.ex       # Oban worker orchestrating the flow
```

### New (Safety domain)

```
lib/ashy_walnut_desk/safety/
├── safety.ex                      # module namespace (no Ash.Domain — no resources)
├── validator.ex                   # behaviour: check/2
├── validator_result.ex            # %Safety.ValidatorResult{} struct
├── validators/
│   ├── baseline.ex                # framework rules (prohibited phrases, guarantees)
│   ├── honest_framing.ex          # runtime AI-body check
│   └── composite.ex               # chains baseline + deployment validators
└── deployment_validator.ex        # behaviour for deployer-supplied extensions
```

### New (Knowledge domain)

```
lib/ashy_walnut_desk/knowledge/
├── knowledge.ex                   # Ash.Domain shell
└── persona.ex                     # Ash.Resource (Phase 4 only — RAG comes Phase 5)
```

### New (Web)

```
lib/ashy_walnut_desk_web/live/
├── persona_live/
│   ├── index.ex                   # admin-only Persona list
│   └── form.ex                    # admin-only Persona create/edit
└── inbox_live/
    └── components/
        ├── generation_panel.ex    # "Generate" + candidate carousel
        └── validator_badge.ex     # pass/fail/violations chip
```

### Modified (existing)

- `lib/ashy_walnut_desk/interaction/draft.ex` — add `:generating` to
  status enum; add `:generate`, `:complete_generation`,
  `:fail_generation` actions; add validation on `:approve` that
  `validator_passed?/1` is true; add `:supersede_others_on_approve`
  change on `:approve` to chain-supersede sibling `:drafting` Drafts
  on the same Inbox.
- `lib/ashy_walnut_desk/interaction/inbox.ex` — read-only association
  helper `latest_drafting_candidates/1` returning Drafts in
  `:drafting | :generating` status, ordered by `created_at`. Used by
  the candidate carousel.
- `lib/ashy_walnut_desk/interaction/changes/chain_link.ex` — add
  three new event types: `:draft_generation_requested`,
  `:draft_generation_completed`, `:draft_generation_failed`. (See §7
  for chain payloads.)
- `lib/ashy_walnut_desk/interaction/checks/` — add
  `from_generation_worker.ex` (parallel to `from_action_worker.ex`)
  gating `:complete_generation` + `:fail_generation` to the worker
  context.
- `lib/ashy_walnut_desk_web/live/inbox_live/show.ex` — mount the
  `GenerationPanel` component; subscribe to
  `Phoenix.PubSub` topic `"draft:#{draft_id}"`.
- `lib/ashy_walnut_desk_web/router.ex` — add `/personas` LV scope
  under the existing admin pipeline.
- `config/config.exs` — extend with `:ai_model_allowlist` (model
  strings, story 4.1), `:ai_adapter_allowlist` (adapter modules,
  parallels channel allowlist — story 4.3), and `:default_model`.
- `config/runtime.exs` — `ANTHROPIC_API_KEY` from env; raise on boot
  if missing in prod.
- `priv/gettext/*.po` — disclosure footer default, validator-violation
  locale keys (all keys; deployer overrides).

### New (Audit)

Three new `AuditEvent` event types:

- `:draft_generation_requested` — payload
  `%{draft_id, inbox_id, persona_id, model, actor_id}`
- `:draft_generation_completed` — payload
  `%{draft_id, inbox_id, model, input_tokens, output_tokens,
    cache_read_tokens, cache_creation_tokens, validator_passed?,
    violations_count}`
- `:draft_generation_failed` — payload
  `%{draft_id, inbox_id, model, error_class, error_detail}`

Plus extension of the existing `:draft_approved` payload to include
`superseded_sibling_draft_ids: [uuid]` so the multi-candidate
supersession is auditable from a single event.

### New (Specs / Decisions)

- `specs/decisions/ADR-025-ai-adapter-via-req.md` (this phase's first
  ADR — see file)
- `specs/decisions/ADR-026-validator-architecture.md` (deferred unless
  the validator composition surface grows during Phase 4
  implementation; recorded here as a placeholder)

### New (Tooling)

- `lib/mix/tasks/phase4.ai.preflight.ex` — checks `ANTHROPIC_API_KEY`
  presence, validates the configured `:default_model` against the
  allowlist, performs a single low-token health-check request against
  Anthropic (skippable via `--skip-network` for offline preflight).
  Exits non-zero on any failure. Mirrors `phase3.webhook.preflight`.

## 3. Ash resources

### 3.1 `Knowledge.Persona` (NEW)

The Phase 4 Knowledge-axis surface. One row per deployment-defined
persona (e.g. "front-desk operator default", "after-hours triage",
"compliance escalation"). Soft-delete + paper-trail.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `name` | string | — | Operator-visible label. |
| `slug` | string | — | URL-safe identifier; unique. |
| `system_prompt` | string | yes | The base system instruction. Cached. Max 8K chars. |
| `disclosure_text` | string | yes | The AI-assistance disclosure appended to every approved draft. Max 500 chars. Gettext-backed default exists; Persona row overrides per-deployment. |
| `guardrail_notes` | string | yes | Free-form deployer notes appended into the prompt's guardrail block. Max 4K chars. Cached. |
| `model_override` | string | — | Nullable. Overrides `:default_model` for drafts generated under this Persona. Must be in `:ai_model_allowlist` (or nil) — validated at `:create`/`:update`. |
| `status` | atom | — | `:active \| :archived`. Default `:active`. |
| `created_at / updated_at` | utc_datetime_usec | — | |
| `deleted_at` | utc_datetime_usec | — | Soft-delete (ADR-019). |

Actions:

- `read` (primary): `filter(expr(is_nil(deleted_at)))`. Authorized
  for admin/operator (operators need to read Personas to drive the
  UI dropdown; they cannot mutate).
- `read_with_archived`: admin only.
- `create`: admin only. Accept all attrs except `id`,
  `created_at/updated_at`, `deleted_at`. Validates `slug`
  uniqueness, `model_override ∈ :ai_model_allowlist OR is nil`,
  `system_prompt` length ≥ 64 chars (basic sanity).
- `update`: admin only. Accept all except `id`, timestamps, `slug`
  (slug is immutable post-create; archive + recreate if you need to
  rename).
- `archive`: admin only. Soft-delete (`SoftDelete` change).
- `recover`: admin only.

Policies:

```elixir
policy action(:read) do
  authorize_if(AdminOrOperator)
end

policy action(:read_with_archived) do
  authorize_if(actor_attribute_equals(:role, :admin))
end

policy action_type([:create, :update, :archive, :recover]) do
  authorize_if(actor_attribute_equals(:role, :admin))
end
```

Field policies: `:system_prompt`, `:disclosure_text`, `:guardrail_notes`,
`:model_override` admin-only. (Operators see name/slug/status only —
they pick a Persona by label without seeing its internals.)

### 3.2 `Interaction.Draft` (MODIFIED)

Two non-schema additions to the status enum + three new actions + one
field policy tweak. **No new columns on the `drafts` table**;
generation provenance reuses the existing `ai_*` fields.

Status enum (was `:drafting | :approved | :superseded | :rejected`)
becomes `:generating | :drafting | :approved | :superseded |
:rejected`. The `:generating` status means "the AI worker is running
or scheduled; body is empty placeholder; not yet operator-reviewable".

New actions:

```elixir
# Operator-triggered. Creates the Draft row in :generating, captures
# persona + model, enqueues the worker. Body is "" placeholder.
create :generate do
  accept([:inbox_id, :persona_id])
  change(set_attribute(:status, :generating))
  change(set_attribute(:body, ""))
  change(StampModelFromPersona)        # NEW change module
  change(EnqueueGenerationWorker)      # NEW change module — Oban.insert
  change({ChainLink, event_type: :draft_generation_requested})
end

# Worker-only. Stamps the AI output + validator result. Transitions
# :generating → :drafting (if validator passed) or stays :generating
# with validator_output set (if failed — operator can :regenerate).
update :complete_generation do
  accept([:body, :ai_prompt, :ai_response, :ai_validator_output])
  require_atomic?(false)
  validate({StatusTransition, from: [:generating]})
  change(SetDraftingIfValidatorPassed)  # NEW: status :drafting if validator_passed?
  change(AppendDisclosureFooter)        # NEW: appends Persona.disclosure_text to :body
  change({ChainLink, event_type: :draft_generation_completed})
end

# Worker-only. Provider error / total validator-impossible state.
update :fail_generation do
  accept([:ai_validator_output])
  require_atomic?(false)
  validate({StatusTransition, from: [:generating]})
  change(set_attribute(:status, :rejected))
  change({ChainLink, event_type: :draft_generation_failed})
end
```

Plus, `:approve` gains a precondition and a side effect:

```elixir
update :approve do
  accept([:compensation_body])
  require_atomic?(false)
  validate(ValidatorPassed)              # NEW: ai_validator_output passed?: true
  change(CompensationAtApproval)
  change(set_attribute(:status, :approved))
  change(set_attribute(:approved_at, &DateTime.utc_now/0))
  change(relate_actor(:approved_by))
  change(SupersedeSiblingDraftCandidates) # NEW: supersede other :drafting on this Inbox
  change({ChainLink, event_type: :draft_approved})
end
```

The `ValidatorPassed` validation reads `ai_validator_output["passed?"]`
from the row and fails the changeset if not `true`. Manual-drafting
flow (Phase 2 `:compose_draft` with operator-typed body) bypasses
the AI validator: in that case `ai_validator_output` is nil and a
separate `Safety.HonestFraming.check/1` is invoked at `:approve`
time against `body`. Same gate, different validator path.

Policies:

```elixir
policy action(:generate) do
  authorize_if(AdminOrOperator)
end

policy action(:complete_generation) do
  authorize_if(FromGenerationWorker)
end

policy action(:fail_generation) do
  authorize_if(FromGenerationWorker)
end
```

`FromGenerationWorker` is a new `Ash.Policy.SimpleCheck` mirroring
`FromActionWorker` from Phase 3 — sets a process-dict marker before
calling and unsets after, with assert-on-mismatch in tests.

Field policies on `ai_prompt / ai_model / ai_response /
ai_validator_output` continue to be admin/operator only (Phase 3 sec
rounds R12 + R13). Nothing changes here; the field-policy posture is
already correct for Phase 4.

### 3.3 `Interaction.Inbox` (MODIFIED, lightweight)

Add a calculated relationship:

```elixir
relationships do
  has_many :latest_drafting_candidates, AshyWalnutDesk.Interaction.Draft do
    destination_attribute(:inbox_id)
    sort(created_at: :asc)
    filter(expr(status in [:generating, :drafting]))
    no_attributes?(false)
  end
end
```

No new columns. No new actions. The candidate carousel reads this
relationship.

## 4. AI subsystem detail

### 4.1 `AI.Adapter` behaviour

```elixir
defmodule AshyWalnutDesk.AI.Adapter do
  @callback complete(%AshyWalnutDesk.AI.Prompt{}, opts :: keyword()) ::
              {:ok, %AshyWalnutDesk.AI.Response{}}
              | {:error, :transient | :permanent | :rate_limited
                       | :content_blocked | :timeout | term()}
end
```

Two impls:

- `AI.Adapters.Anthropic` — Req-direct against
  `POST https://api.anthropic.com/v1/messages`. Sends `model`,
  `max_tokens`, `system` block (with `cache_control` markers), and
  `messages` array. Maps Anthropic error shapes to the callback
  contract. Persists usage block onto the `%AI.Response{}` for the
  worker to write into Draft.
- `AI.Adapters.Fixture` — deterministic test impl. Looks up a canned
  response by `:erlang.phash2/1` of the prompt; falls back to a
  stable placeholder. Configurable simulated latency via opts.

Allowlist lives in `Application.fetch_env!(:ashy_walnut_desk,
:ai_adapter_allowlist)`. The worker resolves the impl by reading
`Application.fetch_env!(:ashy_walnut_desk, :ai_adapter)` so test/dev
swap by env without per-call branching.

### 4.2 `AI.Prompt` struct

```elixir
defstruct [
  :model,
  :max_tokens,
  :system_blocks,        # [%{type: "text", text: ..., cache_control: %{type: "ephemeral"} | nil}]
  :messages,             # [%{role: "user" | "assistant", content: ...}]
  :metadata              # %{draft_id, persona_id, requestor_actor_id}
]
```

Three system blocks emitted by `AI.PromptAssembler.build/1`:

1. **Framework instruction block** — static, baked into the assembler
   module. Sets the meta-rules: "you are drafting; you do not send;
   human review follows; no domain claims you cannot substantiate".
   `cache_control: ephemeral`. ~600 tokens.
2. **Persona block** — concatenation of `Persona.system_prompt` +
   `Persona.guardrail_notes`, prefixed by a stable header.
   `cache_control: ephemeral`. Size capped at 12K characters; the
   assembler refuses to build if exceeded.
3. **Conversation context block** — last N=20 messages from the
   threading `Conversation`, oldest first, rendered as a transcript
   ("Inbound (2026-05-20 14:03): Hello..."). Cache marker NOT set
   — high-churn content.

The user message is the most recent inbound `Message.body` (the
trigger). The assembler does NOT include outbound messages from
prior approved drafts on the same conversation in the user block;
they appear in the system-block transcript instead (so the model
sees them as context, not as the message being replied to).

Token budgeting: assembler trims the conversation block to a 4K
token ceiling (rough char-count heuristic) before invoking. If the
last 20 messages exceed the budget, oldest messages are dropped
first, with a sentinel line ("[earlier history truncated]")
preserved at the top.

Caching contract: the framework + persona blocks are stable across
calls for a given Persona; Anthropic's cache will hit on every call
after the first per (Persona, model) tuple within the cache TTL
(5 min at time of writing). The conversation block is recomputed
every call — accepted cost.

### 4.3 `AI.GenerationWorker`

Oban worker. Queue: `:ai_generation`, max attempts: 3, default
backoff (exponential — 30s, 2m, 5m). Args: `%{"draft_id" => uuid}`.

```text
perform(%{args: %{"draft_id" => draft_id}}):
  draft = Draft.read!(draft_id, actor: system_actor())
  persona = Knowledge.Persona.read!(draft.persona_id, actor: ...)
  conversation = Inbox.conversation_for(draft.inbox_id)
  context_messages = Message.last_n(conversation.id, 20)

  prompt = AI.PromptAssembler.build(%{
    draft: draft, persona: persona,
    conversation: conversation, messages: context_messages
  })

  case AI.Adapter.complete(prompt, model: persona.model_override || default_model()):
    {:ok, response}:
      validator_result = Safety.Validator.check(response.text, persona: persona)
      Draft.complete_generation(draft, %{
        body: response.text,
        ai_prompt: serialize_prompt(prompt),
        ai_response: response.text,
        ai_validator_output: validator_result_to_map(validator_result)
      }, mark_from_generation_worker: true)
      PubSub.broadcast("draft:#{draft.id}", :generation_complete)
      :ok

    {:error, :transient}:
      raise to trigger Oban retry

    {:error, :rate_limited}:
      raise to trigger Oban retry (longer backoff)

    {:error, :permanent}:
      Draft.fail_generation(draft, %{ai_validator_output:
        %{passed?: false, error: :provider_permanent}}, mark_from_generation_worker: true)
      PubSub.broadcast("draft:#{draft.id}", :generation_failed)
      :ok

    {:error, :content_blocked}:
      # Anthropic refused (its own safety stack hit). Same handling
      # as :permanent — operator sees provider-blocked badge and can
      # rewrite manually or regenerate with different prompt context.
      Draft.fail_generation(draft, %{ai_validator_output:
        %{passed?: false, error: :provider_blocked}}, mark_from_generation_worker: true)
      :ok
```

Telemetry events emitted around `complete/2` (start/stop/exception)
and around `Safety.Validator.check/2` (stop only; check is fast).
Token usage from `response.usage` is included in stop metadata so
LiveDashboard renders it without us shipping a custom dashboard.

### 4.4 Anthropic call envelope

```elixir
def complete(%AI.Prompt{} = prompt, opts) do
  body = %{
    model: prompt.model,
    max_tokens: prompt.max_tokens,
    system: Enum.map(prompt.system_blocks, fn block ->
      Map.take(block, [:type, :text, :cache_control])
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end),
    messages: prompt.messages,
    metadata: %{user_id: prompt.metadata.requestor_actor_id}
  }

  Req.post(
    "https://api.anthropic.com/v1/messages",
    headers: [
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ],
    json: body,
    receive_timeout: 60_000
  )
  |> case do
    {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]} = body}} ->
      {:ok, %AI.Response{
        text: text,
        usage: extract_usage(body),
        stop_reason: body["stop_reason"]
      }}
    {:ok, %{status: 429}} -> {:error, :rate_limited}
    {:ok, %{status: s}} when s >= 500 -> {:error, :transient}
    {:ok, %{status: 400, body: %{"error" => %{"type" => "invalid_request_error"}}}} ->
      {:error, :permanent}
    {:ok, %{status: 400}} -> {:error, :content_blocked}
    {:error, %Req.TransportError{}} -> {:error, :transient}
    other -> {:error, {:unexpected, other}}
  end
end
```

`api_key/0` reads from `Application.fetch_env!(:ashy_walnut_desk,
:anthropic_api_key)`. Never logged; never persisted in `ai_*` fields;
never appears in audit payloads.

## 5. Safety subsystem detail

### 5.1 `Safety.Validator` behaviour

```elixir
defmodule AshyWalnutDesk.Safety.Validator do
  @callback check(text :: String.t(), opts :: keyword()) ::
              %AshyWalnutDesk.Safety.ValidatorResult{}
end
```

```elixir
defmodule AshyWalnutDesk.Safety.ValidatorResult do
  defstruct [
    :passed?,                # boolean
    :violations,             # [%{code: atom, severity: :error | :warning,
                            #    span: {start, length} | nil, locale_key: String.t()}]
    :baseline_version,       # string — Safety.Validators.Baseline.version/0
    :deployment_version      # string | nil — version from deployer validator
  ]
end
```

Codes (framework baseline):

- `:guarantee_claim` — phrases like "I guarantee", "we promise that
  [outcome]", language asserting a future outcome the AI cannot
  warrant. Regex + small phrase list.
- `:diagnostic_claim` — clinical / professional-judgment claims when
  no qualifying disclaimer present. Regex catalog reviewed by
  deployer at install; the framework ships a conservative seed list.
- `:pricing_assertion` — currency-amount patterns; pricing must not
  appear in AI drafts unless deployer Persona explicitly allows.
- `:prohibited_phrase` — generic catch-all for deployer-defined
  banned phrases (loaded from Persona.guardrail_notes parse? — TBD
  Phase 4 story; baseline ships an empty list).
- `:honest_framing` — runtime honest-framing check (calls
  `Safety.HonestFraming.check/1`).
- `:length_exceeded` — output exceeds 2_000 chars (Draft.body max).

Severity: `:error` codes set `passed?: false` and block approval.
`:warning` codes leave `passed?: true` but show in the operator
UI. Phase 4 ships only `:error` codes; `:warning` is reserved for
deployer extensions.

### 5.2 `Safety.Validators.Baseline`

Stateless module. `check/2` runs every framework rule above against
the input text and returns a `ValidatorResult`. Pure function except
for the `Safety.HonestFraming` call (also pure).

`version/0` returns a SHA of the module's rule constants, persisted
into `ValidatorResult.baseline_version` so audit chain can prove
which rule set blessed any given Draft. Bumping the rules (a future
PR) changes the SHA and invalidates the cached pass on rerun (an
intentional re-check trigger).

### 5.3 `Safety.HonestFraming` (runtime)

```elixir
defmodule AshyWalnutDesk.Safety.HonestFraming do
  @banned_terms ["unsend", "undo send", "recall message", "take back"]

  def check(text) when is_binary(text) do
    downcased = String.downcase(text)
    Enum.find(@banned_terms, &String.contains?(downcased, &1))
    |> case do
      nil -> :ok
      term -> {:error, term}
    end
  end
end
```

The Phase 2 source-file test (`honest_framing_test.exs`) remains
unchanged — it guards template/gettext copy. Phase 4 adds this
runtime sibling that the Validator invokes against AI body strings.
The two share the banned-terms list via a single source
(`Safety.HonestFraming.banned_terms/0`).

### 5.4 Deployment validator extension point

```elixir
# config/runtime.exs (deployer file)
config :ashy_walnut_desk, :deployment_validators, [
  MyDeployment.Validators.JurisdictionRules,
  MyDeployment.Validators.RegulatedTerminology
]
```

`Safety.Validators.Composite` reads this env and chains the
deployment validators after the baseline. Each deployment validator
implements the same `Safety.Validator` behaviour. Composite returns
the union of violations.

`Application.compile_env/2` is used (not `fetch_env/2`) so missing
config falls back to `[]` cleanly. Deployer-side modules are not
required at compile time; this keeps the framework deployable
empty.

## 6. LiveView components

### 6.1 `PersonaLive.Index` (NEW, admin-only)

Route: `live "/personas", PersonaLive.Index`. Admin-only via the
existing on_mount admin gate. Lists active Personas; click-through
to `PersonaLive.Form` for create/edit. Archived Personas filtered
by `:read_with_archived`.

### 6.2 `PersonaLive.Form` (NEW, admin-only)

Standard `AshPhoenix.Form` over `Knowledge.Persona`. Textareas for
`system_prompt`, `disclosure_text`, `guardrail_notes`; dropdown for
`model_override` populated from the allowlist; submit button gated
on form validity.

### 6.3 `InboxLive.Show` (MODIFIED)

Mounts a new `GenerationPanel` component when
`inbox.latest_drafting_candidates` is empty OR when operator clicks
"Regenerate". Subscribes to `Phoenix.PubSub` topic
`"draft:#{draft_id}"` for each candidate in `:generating` status, so
worker completion re-renders without poll.

### 6.4 `GenerationPanel` component (NEW)

States:

- **No candidates yet**: shows Persona dropdown + "Generate" button.
  Click fires `Draft.:generate`. Component flips to
  generating-spinner.
- **At least one candidate in `:generating`**: shows spinner with
  elapsed time. Cancel button (admin only) calls
  `Draft.:fail_generation` directly with `error: :operator_cancelled`.
- **At least one candidate in `:drafting`**: shows candidate
  carousel; one card per `:drafting` Draft, with validator badge
  (pass / fail + violation codes), body text, "Approve" + "Reject"
  + "Regenerate" actions.
- **All candidates rejected / failed**: same as "no candidates yet"
  with a small note explaining the failed ones (with timestamps).

Cards are visually distinct from manual drafts (a small AI-icon
ribbon) but operators can still type a manual draft via the existing
`:compose_draft` button; the two paths coexist.

### 6.5 `ValidatorBadge` component (NEW)

Renders `ai_validator_output["violations"]` as a row of chips, each
labeled by `gettext("validator.violations.#{code}")`. Hover for
detail. Used on both the carousel cards and the audit-chain viewer.

## 7. Audit chain integration

Each chain event is a row in `audit_events` with `chain_topic =
"inbox:#{inbox_id}"`. Phase 4 adds three new event types; payloads
stamped by `Interaction.Changes.ChainLink` (existing module — adds
new case clauses).

| Event type | Stamped on | Payload |
|---|---|---|
| `:draft_generation_requested` | `Draft.:generate` (create) | `%{draft_id, inbox_id, persona_id, persona_slug, model, actor_id}` |
| `:draft_generation_completed` | `Draft.:complete_generation` | `%{draft_id, inbox_id, model, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, validator_passed?, violations_count, baseline_version, deployment_version}` |
| `:draft_generation_failed` | `Draft.:fail_generation` | `%{draft_id, inbox_id, model, error_class, error_detail_redacted}` |

`error_detail_redacted` is the Anthropic error message with PII
patterns stripped (regex on emails/phone-like patterns). The full
detail goes to logs at `:warning` with the standard sensitive-data
redaction posture from Phase 3 sec rounds.

Existing event extensions:

- `:draft_approved` payload gains
  `superseded_sibling_draft_ids: [uuid]` (empty list for manual
  drafts; populated when the approved Draft was one of multiple
  AI candidates).

`AuditLive.Chain` (Phase 3's TO-14 viewer) automatically picks up
the new event types via the existing rendering — they appear as
ordinary chain entries with their payload visible in the detail
expander. No new viewer code needed.

`mix audit.verify` continues to walk the chain; new events are
hash-chained the same way; nothing in the verifier is event-type
aware.

## 8. Data flow

### 8.1 Operator-triggered generation (happy path)

```text
Operator on InboxLive.Show clicks "Generate"
  → GenerationPanel.handle_event("generate", %{"persona_id" => pid})
  → Draft.:generate %{inbox_id: ..., persona_id: pid}
      change set_attribute :status :generating
      change set_attribute :body ""
      change StampModelFromPersona       → reads persona.model_override
      change EnqueueGenerationWorker     → Oban.insert(GenerationWorker,
                                                       %{draft_id: id})
      change ChainLink :draft_generation_requested
  → returns Draft row id (status :generating)
  → LV re-renders carousel with spinner card for this Draft
  → LV subscribes to PubSub "draft:#{id}"
  → Oban worker fires (default <1s):
      load Draft + Persona + Conversation + last-20 Messages
      prompt = AI.PromptAssembler.build/1
      response = AI.Adapter.complete(prompt, model: ...)
      validator = Safety.Validator.check(response.text, persona: persona)
      Draft.:complete_generation %{body: response.text,
                                   ai_prompt: serialize_prompt(prompt),
                                   ai_response: response.text,
                                   ai_validator_output: result_map(validator)}
          change SetDraftingIfValidatorPassed     → status :drafting | :generating
                                                    (failed validator stays :generating
                                                     with output set; operator can
                                                     :regenerate or :reject)
          change AppendDisclosureFooter           → body <> "\n\n" <> persona.disclosure_text
          change ChainLink :draft_generation_completed
      PubSub.broadcast("draft:#{id}", :generation_complete)
  → operator UI re-renders: spinner → candidate card with validator badge
  → operator reviews; clicks "Approve" on chosen card
  → Draft.:approve (existing Phase 2 chain)
      validate ValidatorPassed                    → reads ai_validator_output.passed?
      change CompensationAtApproval               → existing
      change SupersedeSiblingDraftCandidates      → NEW: every other :drafting on
                                                   the same Inbox gets :supersede
                                                   in a single transaction
      change ChainLink :draft_approved            → payload now includes
                                                    superseded_sibling_draft_ids
  → 5-second countdown (Phase 2 mechanic)
  → Action.:execute / Twilio (Phase 3, unchanged)
```

### 8.2 Validator-failed generation

```text
... worker generates ...
  response.text contains a phrase matching :guarantee_claim regex
  validator.passed? == false
  validator.violations == [%{code: :guarantee_claim, severity: :error,
                             span: {142, 17}, locale_key: "validator.violations.guarantee_claim"}]
  Draft.:complete_generation runs
    SetDraftingIfValidatorPassed → status stays :generating (not promoted to :drafting)
    AppendDisclosureFooter        → still appends (operator sees the full thing)
    ChainLink :draft_generation_completed (with validator_passed?: false)
  PubSub.broadcast → :generation_complete (with failure flag in metadata)
  operator UI: candidate card renders with :error-state ValidatorBadge,
    body visible but greyed, "Approve" disabled, "Regenerate" + "Reject" enabled
  operator either:
    a. Clicks Regenerate → new Draft.:generate (new Draft row, same flow)
    b. Clicks Reject → Draft.:reject on this Draft (status :rejected,
                       audit chain captures with no winner)
    c. Manually edits via Draft.:revise (operator types new body;
                       Safety.HonestFraming check fires at :approve time)
```

Note: a validator-failed Draft does NOT transition to `:rejected`
automatically. The operator decides — sometimes a "guarantee" phrase
is exactly what compliance wants in context, and the operator
overrides by typing a revised version that doesn't trigger the
regex. The audit chain captures both decisions.

### 8.3 Provider failure

```text
Anthropic returns 503 (transient).
  Adapter returns {:error, :transient}.
  Worker raises → Oban retries (30s, then 2m, then 5m).
  After 3 attempts, Oban marks job as discarded.
  Worker's terminal-failure handler fires Draft.:fail_generation:
    status :generating → :rejected
    ai_validator_output set to %{passed?: false, error: :provider_transient_exhausted}
    ChainLink :draft_generation_failed
  PubSub.broadcast :generation_failed
  operator UI: spinner card flips to error card with "Provider unavailable.
    Try again, or type a draft manually."
```

For `:permanent` and `:content_blocked` errors, the worker fails on
the first attempt (no retry) and surfaces the corresponding error
class. The operator sees actionable copy ("Provider rejected this
prompt — try a different Persona or shorten the conversation context")
not raw Anthropic error strings.

### 8.4 Multi-candidate approval

When operator generates twice (regenerate path), the Inbox has two
Drafts in `:drafting` status. Both visible in the carousel. Operator
clicks "Approve" on Draft B:

```text
Draft.:approve on B:
  validate ValidatorPassed
  change SupersedeSiblingDraftCandidates:
    for each Draft on inbox_id where status: :drafting and id != B.id:
      Draft.:supersede(d, actor: operator, authorize?: true)
      (each :supersede stamps its own ChainLink :draft_superseded event —
       so a multi-candidate approval generates 1 + N audit events for
       a clear forensic trail)
  ...rest of :approve unchanged
```

`SupersedeSiblingDraftCandidates` runs in the same transaction as
`:approve`, so either all transitions land or none — no half-state
where multiple candidates remain `:drafting` after an approval.

## 9. External integrations

### 9.1 Anthropic Messages API

- Endpoint: `POST https://api.anthropic.com/v1/messages`
- Auth: `x-api-key` header with `ANTHROPIC_API_KEY` env var.
- Required headers: `anthropic-version: 2023-06-01`,
  `content-type: application/json`.
- Body shape per §4.4.
- Rate limits: per-account; we treat 429 as `:rate_limited` and
  let Oban back off.
- Default model: `claude-sonnet-4-6` for Phase 4 launch (resolved §7
  Q6 — see §11). Persona can override to Opus 4.7 for cases that
  need it.
- Prompt caching: `cache_control: %{type: "ephemeral"}` markers on
  the framework + persona system blocks. Cache hit returns
  `cache_read_input_tokens` in usage; we persist these per call.
  Minimum block size for cacheability on Sonnet/Opus is ~1024
  tokens at the time of writing — the framework block alone meets
  this; the persona block usually does once `system_prompt +
  guardrail_notes` is filled.

### 9.2 No webhook side

Phase 4 does not introduce any inbound channel from Anthropic.
There is no streaming/async response handling (Phase 6+ if needed);
generation completes within a single synchronous Req call inside
the worker.

## 10. Migration impact

### 10.1 Database

One Ecto migration for the `Knowledge.Persona` table (Ash generates
via `mix ash_postgres.generate_migrations`):

- `knowledge_personas` table with attrs per §3.1, indexed on
  `slug` (unique partial: `WHERE deleted_at IS NULL`), `status`.

One Ecto migration for the `Draft` status enum:

- Adds `:generating` as a valid value. Since `status` is currently
  modeled as `atom` with `constraints(one_of: [...])`, Ash treats
  this as a config change — no SQL alter. The check is at the
  changeset layer. Migration is structural only if we add a check
  constraint at DB level (we currently don't — Phase 2 did not).

No other schema changes. The `ai_*` fields on Draft already exist
from Phase 2; the `audit_events` table already supports arbitrary
event_type strings via the existing `payload` JSONB column.

### 10.2 Configuration

- `:anthropic_api_key` — required in prod (raise on boot if
  missing); optional in dev/test (Fixture adapter used instead).
- `:ai_adapter` — atom, default `AshyWalnutDesk.AI.Adapters.Anthropic`
  in prod, `AshyWalnutDesk.AI.Adapters.Fixture` in test.
- `:ai_adapter_allowlist` — list of adapter **module** atoms (e.g.
  `AshyWalnutDesk.AI.Adapters.Anthropic`, `…Fixture`); the AI analog
  of `:channel_adapters`. Introduced by story 4.3 (the adapter story),
  not 4.1.
- `:ai_model_allowlist` — list of model **strings** a Persona may
  select via `model_override` (default
  `["claude-sonnet-4-6", "claude-opus-4-7"]`). Distinct from
  `:ai_adapter_allowlist`: one gates which provider module runs, the
  other gates which model string a deployer-authored Persona may name.
  Story 4.1 ships this (Persona validates `model_override` against it);
  `Persona.model_override` is rejected at `:create`/`:update` if the
  value is non-nil and absent from this list.
- `:default_model` — string, default `"claude-sonnet-4-6"`.
- `:default_max_tokens` — integer, default 1024.
- `:deployment_validators` — list of modules, default `[]`.

Most read via `Application.fetch_env/2`; the two allowlists are read
via `Application.compile_env/2` where they back compile-time
attributes (e.g. `Persona`'s `@allowed_models`).

### 10.3 Data backfill

None. New rows created from `:generate` onward use the new shape;
existing Drafts (Phase 2/3 manually composed) continue to work
through `:compose_draft` + `:approve` with no AI fields populated
(those rows' `ai_validator_output` is nil, and `:approve`'s
`ValidatorPassed` validation handles the nil case by falling through
to `Safety.HonestFraming.check/1` against `body`).

## 11. Resolved open questions

Numbered against requirements §7. Architect resolutions; reviewable
on Architect-stage gate.

- **Q1 — Validator contract.** **Pass/fail + categorized violation
  codes.** Schema per §5.1. Codes drive gettext labels (`validator.
  violations.#{code}`), enable per-code analytics, and keep the
  audit chain interpretable. Pure pass/fail loses the ability to
  show operators *why* something failed.
- **Q2 — Viewer access to generation.** **Operator/admin only for
  `:generate`. Viewers read Drafts under existing field policies.**
  Phase 3 sec rounds R12/R13 already gate the `ai_*` fields; viewers
  see Draft status + FKs but not body/prompt/response. No new viewer
  surface in Phase 4.
- **Q3 — Conversation context window.** **Last N=20 messages, oldest
  first, capped at 4K-token budget.** Trimming drops oldest first
  with a "earlier history truncated" sentinel. Configurable via
  `Application.get_env(:ashy_walnut_desk, :ai_context_window, 20)`
  for deployer tuning (Phase 4 ships the default; story-level may
  expose this in PersonaLive form later).
- **Q4 — Disclosure text mutability.** **Immutable at generation
  time; appended server-side; operator cannot strip.**
  `AppendDisclosureFooter` change runs on `:complete_generation`
  and writes the footer into `Draft.body`. Operator's `:revise`
  action accepts `:body` but the next `:approve` re-runs the
  validator (which includes a check that the disclosure footer is
  present — see story decomposition). If a deployer changes the
  Persona's `disclosure_text` mid-flight, in-flight Drafts retain
  their original footer; that's the audit-correct behavior.
- **Q5 — Regenerate semantics.** **Multi-candidate coexist; explicit
  operator selection via `:approve`.** Approval auto-supersedes
  sibling `:drafting` candidates in the same transaction. Operator
  can also manually `:supersede` or `:reject` individual candidates.
  The chain captures everything.
- **Q6 — Model selection.** **Deployment-fixed default
  (`claude-sonnet-4-6`); per-Persona override allowed; per-draft
  operator picker deferred.** Stops operators from "shopping" for a
  model that bypasses validator triggers; admins can introduce a
  Opus-using Persona explicitly when the case warrants. Rationale:
  Sonnet 4.6 is the default workhorse balance for regulated-services
  drafts (latency ~2-4s, strong instruction following). Opus 4.7
  available via Persona override for harder cases.
- **Q7 — Telemetry floor.** **`:telemetry` events around generation
  and validator; usage block persisted on `ai_response`.** Events
  per §4.3. Phoenix.LiveDashboard renders without custom code; a
  per-deployment Grafana scrape can pull from telemetry handlers if
  desired (deployer responsibility). Audit chain payloads include
  token counts so post-hoc cost analysis is queryable.
- **Q8 — `ash_ai` vs Req-direct.** **Req-direct via new
  `AI.Adapter` behaviour.** Decided in ADR-025 (this phase). The
  adapter boundary leaves the door open for a future `Adapters.AshAi`
  impl when `ash_ai` stabilizes.

## 12. Risks revisited (Architect-side)

The requirements §6 risks remain valid. Architect-stage additions:

- **Anthropic API key sprawl across environments.** Mitigation:
  `phase4.ai.preflight` mix task validates presence on prod boot;
  CI uses Fixture adapter exclusively (no API key needed in CI).
- **Prompt cache invalidation surprises.** A small change to the
  framework block invalidates the cache cluster-wide and the first
  call after deploy is full-price. Mitigation: framework block is
  stable, only changed in deliberate "prompt update" PRs; telemetry
  surfaces cache hit ratio so regressions show up.
- **Persona content as exfiltration vector.** A malicious admin
  could put sensitive data into `system_prompt` or `guardrail_notes`
  and have it persisted into Anthropic. Mitigation: Persona policies
  restrict create/update to admin role; AshPaperTrail captures every
  Persona change for forensic review.
- **Validator false-positives during operator high-volume work.**
  Aggressive regex could block legitimate drafts in clusters.
  Mitigation: Phase 4 story includes telemetry-driven validator
  sensitivity tuning before phase close; the `:warning` severity
  channel exists as a release valve for ambiguous patterns.
- **Worker queue starvation when one Persona's prompt is slow.** A
  Persona using Opus with deep conversation context could occupy
  worker slots for 30s+. Mitigation: separate queue `:ai_generation`
  (not sharing with `:outbound`); concurrency tuned per deployment
  Application env.

## 13. Testing posture

Per AGENTS.md §5 / §6, `just verify` must stay green.

### 13.1 Unit

- `AI.PromptAssembler` — token-budget trimming; cache_control marker
  presence; persona-block composition; system-block stability across
  calls (snapshot-style).
- `AI.Adapters.Anthropic` — error-classification table (200/429/5xx/
  400-invalid_request/400-other/transport); Req mock.
- `AI.Adapters.Fixture` — determinism (same prompt → same response);
  configurable latency.
- `Safety.Validators.Baseline` — one test per code, positive +
  negative.
- `Safety.HonestFraming.check/1` — banned-term match table.
- `Safety.Validators.Composite` — deployer validator chained after
  baseline; union of violations.

### 13.2 Resource

- `Draft.:generate` — happy path; persona missing; non-allowlisted
  model_override; concurrent `:generate` calls on the same Inbox
  (both succeed, both rows created — multi-candidate).
- `Draft.:complete_generation` — only callable from worker
  (`FromGenerationWorker` check); validator-pass and validator-fail
  state transitions; disclosure footer appended; PaperTrail captures.
- `Draft.:approve` — `ValidatorPassed` validation blocks when
  `ai_validator_output["passed?"]` is false; sibling supersede
  fires in single transaction.

### 13.3 Adapter conformance

`AI.Adapter` conformance suite (parallel to Phase 3's adapter
conformance) — both `Anthropic` (against a mocked Req) and
`Fixture` satisfy the same contract: callback signature, error-class
mapping, response shape.

### 13.4 Integration

- LV: `InboxLive.Show` with `GenerationPanel` — generate, render
  spinner, render candidate card on completion, validator badge
  visible.
- Audit chain: `mix audit.verify` green after a generation run +
  approval + supersede.
- Honest-framing source-file test continues to scan only
  `lib/ashy_walnut_desk_web` + `priv/gettext` (no false positives
  from AI worker code paths).

### 13.5 Property

- Multi-candidate ordering: `latest_drafting_candidates` returns
  Drafts in `created_at` ascending regardless of insert order.
- Token budget: assembler output is always `≤ budget` regardless of
  conversation length.
- Validator: for any baseline pass on text T, the validator on
  `T <> persona.disclosure_text` is also a pass (disclosure
  shouldn't trigger framework rules).

### 13.6 Phase-4-level regression gate

`mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs &&
mix audit.verify && mix test test/ashy_walnut_desk/ai/conformance_test.exs`
runs in the integration story (Phase 4 story 4.N — PM decides).

## 14. Rollback

Phase 4 introduces no irreversible schema changes. Rollback path:

1. Disable the `GenerationPanel` LV component (feature flag via
   Application env `:phase_4_ai_generation_enabled, default true`).
   Hides the "Generate" button. Existing Drafts in `:generating`
   stay parked; admins can `:fail_generation` them with
   `error: :phase_rolled_back`.
2. Persona resource can be left in place (no harm — no FK from
   other tables except via Draft, which keeps the `persona_id`
   nullable on rows that predate the FK).
3. Anthropic API key removal: app continues to boot if the
   `:ai_adapter` is swapped to `Fixture` or if `:phase_4_ai_
   generation_enabled` is false.
4. No data backfill or destructive ALTER required to revert.

This is intentional: Phase 4 is additive and gated by the
feature-flag pattern Phase 3 already established for adapters.

## 15. ADRs introduced

- **ADR-025: Req-direct Anthropic via internal `AI.Adapter`
  behaviour (not ash_ai).** Filed. See
  `specs/decisions/ADR-025-ai-adapter-via-req.md`.

A second ADR (validator architecture) is intentionally not filed
in this phase. The validator composite + baseline + deployment-
extension pattern is straightforward enough that it doesn't warrant
a standalone decision document unless a story-level discovery shows
otherwise. If during PM/implementation we find ourselves debating
the validator shape across multiple stories, that's the signal to
backfill ADR-026.

## 16. Story-breakdown hints for PM

(Not the story breakdown — PM writes that into requirements §4.
This list is hints, not constraints.)

The natural decomposition of Phase 4 work, in approximate dependency
order:

- Foundation: `Knowledge` domain + `Persona` resource + admin LV
  surface.
- AI subsystem skeleton: `AI.Adapter` behaviour + `AI.Adapters.
  Fixture` (test-only) + `AI.Prompt` + `AI.Response` structs +
  `AI.PromptAssembler` (no Anthropic call yet).
- Anthropic real impl: `AI.Adapters.Anthropic` + Req mock tests +
  conformance suite.
- Safety subsystem: `Safety.Validator` behaviour + `Validators.
  Baseline` + `HonestFraming` runtime + `Composite` + deployment-
  extension wiring.
- Draft generation actions: `:generate`, `:complete_generation`,
  `:fail_generation`, `FromGenerationWorker` check; `:approve`
  precondition + sibling supersede.
- Oban worker: `GenerationWorker` orchestrating the full flow;
  telemetry events.
- LV surface: `GenerationPanel`, `ValidatorBadge`, integration with
  `InboxLive.Show`.
- Phase 4 entry gate: `mix phase4.ai.preflight`.
- Phase 4 integration gate: regression suite + telemetry-driven
  validator sensitivity tuning + deployer docs.

PM is free to slice / merge as they see fit; the constraint is that
each story stays 1–3 hours per AGENTS.md §2.
