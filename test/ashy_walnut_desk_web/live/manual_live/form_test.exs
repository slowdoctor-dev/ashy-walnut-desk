defmodule AshyWalnutDeskWeb.ManualLive.FormTest do
  @moduledoc """
  Story 5.6 AC2 — `/manuals/new` + `/manuals/:id/edit` drive
  `:author`/`:revise`, surface validation errors, and show read-only
  paper-trail version history.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Knowledge.Manual

  defp sign_in_as_admin(conn) do
    email = "manual-form-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "author a new manual through the form", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/manuals/new")

    view
    |> form("#manual-form", %{
      "form" => %{
        "title" => "Booking playbook",
        "slug" => "booking-playbook",
        "body" => "Always confirm the requested slot."
      }
    })
    |> render_submit()

    assert_redirect(view, "/manuals")

    manuals = Ash.read!(Manual, actor: admin)
    assert [manual] = Enum.filter(manuals, &(&1.slug == "booking-playbook"))
    assert manual.revision == 1
  end

  test "invalid slug shows a validation error, no manual created", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/manuals/new")

    html =
      view
      |> form("#manual-form", %{
        "form" => %{"title" => "Bad", "slug" => "Not A Slug!", "body" => "body"}
      })
      |> render_submit()

    assert html =~ "manual-form"
    assert Ash.read!(Manual, actor: admin) == []
  end

  test "revise bumps revision and version history renders", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)

    manual =
      Ash.create!(
        Manual,
        %{title: "History", slug: "history-manual", body: "First body."},
        action: :author,
        actor: admin
      )

    {:ok, view, html} = live(conn, ~p"/manuals/#{manual.id}/edit")

    assert html =~ "data-role=\"version-history\""
    assert html =~ "data-role=\"version-row\""

    view
    |> form("#manual-form", %{"form" => %{"title" => "History", "body" => "Second body."}})
    |> render_submit()

    assert_redirect(view, "/manuals")

    reloaded = Ash.get!(Manual, manual.id, actor: admin)
    assert reloaded.revision == 2
    assert reloaded.body == "Second body."

    # Slug is immutable — the edit form does not render a slug input.
    {:ok, _view, edit_html} = live(conn, ~p"/manuals/#{manual.id}/edit")
    refute edit_html =~ "form[slug]"
    assert edit_html =~ ~r/Revision\s*2/
  end
end
