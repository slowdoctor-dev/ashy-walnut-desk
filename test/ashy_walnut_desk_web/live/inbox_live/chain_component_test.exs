defmodule AshyWalnutDeskWeb.InboxLive.ChainComponentTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders four-stage stepper with honest framing", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, ~p"/inbox")

    html =
      render_component(AshyWalnutDeskWeb.InboxLive.ChainComponent,
        id: "chain-test",
        inbox: %{status: :open, draft: nil, action: nil, compensation: nil}
      )

    assert html =~ "Inbox"
    assert html =~ "Draft"
    assert html =~ "Action"
    assert html =~ "Compensation"
    refute html =~ "unsend"
    refute html =~ "undo send"
    refute html =~ "recall"
  end
end
