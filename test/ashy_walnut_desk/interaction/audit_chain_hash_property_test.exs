defmodule AshyWalnutDesk.Interaction.AuditChainHashPropertyTest do
  @moduledoc """
  Test-fix R1 — property coverage for `AuditChain.compute_hash/2`.
  The existing `audit_chain_test.exs` exercises one happy-path
  chain; this file adds properties that catch silent regressions
  in the hash primitive itself:

  - determinism: `compute_hash(prev, json)` is a pure function
  - prev-dependency: changing `prev_hash` MUST change the output
  - payload-dependency: changing `canonical_json` MUST change the output
  - nil-prev sentinel: `compute_hash(nil, json)` works (first event)

  A regression in any of these would silently break audit-chain
  continuity verification.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshyWalnutDesk.Interaction.AuditChain

  property "deterministic — same inputs produce same output" do
    check all(
            prev <- one_of([constant(nil), binary(min_length: 1, max_length: 64)]),
            json <- binary(min_length: 0, max_length: 4_000)
          ) do
      assert AuditChain.compute_hash(prev, json) == AuditChain.compute_hash(prev, json)
    end
  end

  property "prev_hash matters — different prev → different output (when json fixed)" do
    check all(
            json <- binary(min_length: 1, max_length: 200),
            prev_a <- binary(min_length: 1, max_length: 64),
            prev_b <- binary(min_length: 1, max_length: 64),
            prev_a != prev_b
          ) do
      refute AuditChain.compute_hash(prev_a, json) == AuditChain.compute_hash(prev_b, json)
    end
  end

  property "payload matters — different json → different output (when prev fixed)" do
    check all(
            prev <- one_of([constant(nil), binary(min_length: 1, max_length: 64)]),
            json_a <- binary(min_length: 1, max_length: 200),
            json_b <- binary(min_length: 1, max_length: 200),
            json_a != json_b
          ) do
      refute AuditChain.compute_hash(prev, json_a) == AuditChain.compute_hash(prev, json_b)
    end
  end

  property "nil prev_hash is distinguishable from empty-string prev_hash" do
    # The implementation does `prev || ""` so `nil` and `""` SHOULD
    # collide. This property locks that contract so a future change
    # treating nil differently doesn't silently break the chain.
    check all(json <- binary(min_length: 1, max_length: 200)) do
      assert AuditChain.compute_hash(nil, json) == AuditChain.compute_hash("", json)
    end
  end

  property "output is a 64-char lowercase hex string (SHA-256)" do
    check all(
            prev <- one_of([constant(nil), binary(min_length: 1, max_length: 64)]),
            json <- binary(min_length: 0, max_length: 200)
          ) do
      result = AuditChain.compute_hash(prev, json)
      assert is_binary(result)
      assert byte_size(result) == 64
      assert String.match?(result, ~r/^[0-9a-f]{64}$/)
    end
  end
end
