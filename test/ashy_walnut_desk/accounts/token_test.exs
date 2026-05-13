defmodule AshyWalnutDesk.Accounts.TokenTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshOban.Info, as: ObanInfo
  alias AshyWalnutDesk.Accounts.Token

  test "jti is marked sensitive" do
    attr = Info.attribute(Token, :jti)
    assert attr.sensitive?
  end

  test "public actor cannot read tokens" do
    assert {:ok, false} = Ash.can({Token, :read, %{}}, actor: nil)
  end

  describe "expunge_tokens AshOban trigger" do
    test "is configured to call :expunge_expired daily at 03:00 UTC" do
      trigger = ObanInfo.oban_trigger(Token, :expunge_tokens)

      assert trigger, "expected an :expunge_tokens trigger on AshyWalnutDesk.Accounts.Token"
      assert trigger.action == :expunge_expired
      assert trigger.read_action == :expired
      assert trigger.scheduler_cron == "0 3 * * *"
      assert trigger.queue == :tokens
    end

    test "destroys expired rows and leaves unexpired rows intact" do
      now = DateTime.utc_now()
      expired_at = DateTime.add(now, -3600, :second)
      future_at = DateTime.add(now, 3600, :second)

      Ash.Seed.seed!(Token, %{
        jti: "expired-jti-1.8",
        subject: "user?id=expired",
        purpose: "user",
        expires_at: expired_at
      })

      Ash.Seed.seed!(Token, %{
        jti: "live-jti-1.8",
        subject: "user?id=live",
        purpose: "user",
        expires_at: future_at
      })

      assert %{failure: 0} =
               AshOban.Test.schedule_and_run_triggers({Token, :expunge_tokens})

      remaining_jtis =
        Token
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.jti)

      refute "expired-jti-1.8" in remaining_jtis
      assert "live-jti-1.8" in remaining_jtis
    end
  end
end
