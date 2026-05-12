defmodule AshyWalnutDeskWeb.WelcomeLive do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_optional}

  @project_name "ashy-walnut-desk"

  @impl true
  def mount(_params, _session, socket) do
    version = to_string(Application.spec(:ashy_walnut_desk, :vsn))

    {:ok,
     assign(socket,
       project_name: @project_name,
       version: version
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl space-y-6 px-6 py-12">
      <h1 class="text-3xl font-semibold">{gettext("Welcome")}</h1>

      <p>
        <span class="font-medium">{gettext("Project")}: </span>{@project_name}
      </p>

      <p>
        <span class="font-medium">{gettext("Version")}: </span>{@version}
      </p>

      <%= if @current_user do %>
        <p>
          <span class="font-medium">{gettext("Signed in as")}: </span>{@current_user.email}
        </p>

        <.link href={~p"/sign-out"} method="delete">{gettext("Sign out")}</.link>
      <% else %>
        <.link href={~p"/sign-in"}>{gettext("Sign in")}</.link>
      <% end %>
    </div>
    """
  end
end
