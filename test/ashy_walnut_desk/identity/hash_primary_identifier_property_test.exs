defmodule AshyWalnutDesk.Identity.HashPrimaryIdentifierPropertyTest do
  @moduledoc """
  Test-fix R1 — property coverage for the
  `HashPrimaryIdentifier` change. The normalizer strips whitespace,
  hyphens, and parens from human-formatted phone numbers (e.g.
  `"+1 (555) 123-4567"` → `"+15551234567"`) before hashing. The
  hash drives inbound-webhook identity lookup; a normalization
  regression would silently fail to match repeat senders.

  This file asserts that EVERY format variant of the same logical
  E.164 number produces the same hash.
  """

  use AshyWalnutDesk.DataCase, async: false
  use ExUnitProperties

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.Identity

  defp register_with(admin, identifier) do
    Ash.create(
      Identity,
      %{display_name: "T-#{System.unique_integer([:positive])}", primary_identifier: identifier},
      action: :register_identity,
      actor: admin
    )
  end

  defp format_variants(digits) do
    # `digits` is the bare numeric tail without the leading `+`.
    # Generate visually-distinct but semantically-identical formats.
    base = "+" <> digits

    [
      base,
      "+" <> insert_at(digits, 1, " "),
      "+" <> insert_at(digits, 1, "-"),
      ("+" <> insert_at(digits, 1, " (")) |> insert_at(5, ") "),
      "  " <> base <> "  ",
      base |> String.upcase()
    ]
  end

  defp insert_at(s, i, fragment) do
    {a, b} = String.split_at(s, i)
    a <> fragment <> b
  end

  # Only one admin per transaction (users_one_admin_idx). Mint once.
  setup do
    %{admin: AccountsFixtures.create_user(:admin)}
  end

  property "all format variants of the same E.164 hash to the same value", %{admin: admin} do
    check all(digits <- string([?0..?9], min_length: 6, max_length: 14), max_runs: 10) do
      variants = format_variants(digits)
      [first | rest] = variants

      {:ok, first_id} = register_with(admin, first)

      for fmt <- rest do
        case register_with(admin, fmt) do
          {:ok, ident} ->
            assert ident.primary_identifier_hash == first_id.primary_identifier_hash,
                   "format #{inspect(fmt)} hashed differently from #{inspect(first)}"

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            # The unique-hash constraint added in R6 of the security
            # iteration rejects the second create with the same hash.
            # That's the EXPECTED behaviour and proves the variants
            # normalize identically. Any other rejection is a bug.
            assert Enum.any?(errors, fn err ->
                     match?(
                       %Ash.Error.Changes.InvalidAttribute{
                         private_vars: [{:constraint, _} | _]
                       },
                       err
                     )
                   end),
                   "expected unique-hash violation for variant #{inspect(fmt)}, got: #{inspect(errors)}"
        end
      end
    end
  end
end
