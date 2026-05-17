defmodule AshyWalnutDesk.Accounts.Emails do
  @moduledoc false

  import Swoosh.Email
  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  alias AshyWalnutDesk.Mailer

  def deliver_magic_link(user_or_email, url) do
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    escaped_email = escape_html(email)
    escaped_url = escape_html(url)

    new()
    |> to(to_string(email))
    |> from({"Ashy Walnut Desk", "noreply@example.test"})
    |> subject("Magic sign-in link")
    |> html_body("""
    <p>Hello #{escaped_email},</p>
    <p><a href="#{escaped_url}">Click here to sign in</a>.</p>
    """)
    |> text_body("Hello #{email}, visit #{url} to sign in.")
    |> Mailer.deliver()
  end

  defp escape_html(value), do: value |> to_string() |> html_escape() |> safe_to_string()
end
