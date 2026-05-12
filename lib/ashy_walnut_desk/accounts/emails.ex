defmodule AshyWalnutDesk.Accounts.Emails do
  @moduledoc false

  import Swoosh.Email

  alias AshyWalnutDesk.Mailer

  def deliver_magic_link(user_or_email, url) do
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    new()
    |> to(to_string(email))
    |> from({"Ashy Walnut Desk", "noreply@example.test"})
    |> subject("Magic sign-in link")
    |> html_body("""
    <p>Hello #{email},</p>
    <p><a href="#{url}">Click here to sign in</a>.</p>
    """)
    |> text_body("Hello #{email}, visit #{url} to sign in.")
    |> Mailer.deliver()
  end
end
