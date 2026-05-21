defmodule AshyWalnutDeskWeb.InboxLive.ValidatorBadgeTest do
  use AshyWalnutDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AshyWalnutDeskWeb.InboxLive.Components.ValidatorBadge

  test "renders passed state" do
    html =
      render_component(ValidatorBadge,
        id: "badge-passed",
        validator_output: %{"passed?" => true, "violations" => []}
      )

    assert html =~ "Validation passed"
  end

  test "renders failure state with a human-readable violation message" do
    html =
      render_component(ValidatorBadge,
        id: "badge-failed",
        validator_output: %{
          "passed?" => false,
          "violations" => [%{"code" => "honest_framing"}]
        }
      )

    assert html =~ "Validation failed"
    # The gettext key resolves to its English translation, not the raw key.
    assert html =~ "Implies a delivered message can be retracted or reversed"
    refute html =~ "validator.violations.honest_framing"
  end

  test "handles forbidden validator field gracefully" do
    html =
      render_component(ValidatorBadge,
        id: "badge-restricted",
        validator_output: %Ash.ForbiddenField{}
      )

    assert html =~ "Validation restricted"
    refute html =~ "validator.violations"
  end
end
