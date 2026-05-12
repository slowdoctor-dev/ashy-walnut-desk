defmodule AshyWalnutDesk.Accounts.TokenTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.Token

  test "jti is marked sensitive" do
    attr = Info.attribute(Token, :jti)
    assert attr.sensitive?
  end

  test "public actor cannot read tokens" do
    assert {:ok, false} = Ash.can({Token, :read, %{}}, actor: nil)
  end
end
