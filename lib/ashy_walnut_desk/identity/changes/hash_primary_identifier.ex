defmodule AshyWalnutDesk.Identity.Changes.HashPrimaryIdentifier do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset

  # Sec-fix R3: catch obviously-malformed identifiers (empty, no
  # leading `+`, SQL-shaped, > 15 digits). The pre-normalize step
  # strips whitespace, hyphens, and parens so callers can pass
  # human-formatted numbers like `"+1 (555) 123-4567"`. After
  # normalization the canonical form is bare `+` + digits — which
  # is also what Twilio expects in `To:`.
  #
  # Doesn't validate country code assignment (that's a
  # libphonenumber-class problem deployers can layer in their
  # private repo).
  @e164_regex ~r/^\+\d{6,15}$/

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, &apply_identifier/1)
  end

  defp apply_identifier(changeset) do
    case Changeset.get_argument(changeset, :primary_identifier) do
      nil -> changeset
      raw -> stamp_or_reject(changeset, normalize_identifier(raw))
    end
  end

  defp stamp_or_reject(changeset, normalized) do
    if Regex.match?(@e164_regex, normalized) do
      stamp(changeset, normalized)
    else
      reject(changeset, normalized)
    end
  end

  defp stamp(changeset, normalized) do
    salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)
    hash = :crypto.hash(:sha256, normalized <> salt) |> Base.encode16(case: :lower)

    changeset
    |> Changeset.force_change_attribute(:primary_identifier_hash, hash)
    # Story 3.fix: persist the raw identifier (sensitive) so the
    # outbound adapter has a recipient to send to. The hash remains
    # the lookup key; this is payload only.
    |> Changeset.force_change_attribute(:primary_identifier, normalized)
  end

  defp reject(changeset, normalized) do
    Changeset.add_error(changeset,
      field: :primary_identifier,
      message:
        "must be E.164 (e.g., +15551234567) — got #{inspect(String.slice(normalized, 0, 40))}"
    )
  end

  defp normalize_identifier(raw) do
    raw
    |> to_string()
    |> String.replace(~r/[\s\-().]/u, "")
    |> String.downcase()
  end
end
