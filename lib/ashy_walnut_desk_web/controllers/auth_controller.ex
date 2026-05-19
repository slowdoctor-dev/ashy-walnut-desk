defmodule AshyWalnutDeskWeb.AuthController do
  use AshyWalnutDeskWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = safe_return_to(get_session(conn, :return_to))

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = safe_return_to(get_session(conn, :return_to))

    conn
    |> clear_session(:ashy_walnut_desk)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end

  # Only accept relative same-origin paths. Reject protocol-relative
  # (`//evil.com`), backslash-prefixed paths some browsers normalize
  # to URLs, anything with a scheme/host, or whitespace prefixes that
  # could bypass naive `String.first/1` checks.
  #
  # Defense-in-depth: today AshAuthentication only writes
  # `Phoenix.Controller.current_path/1` into `:return_to` (path-only),
  # but any future plug/controller setting it from user input must
  # not become an open-redirect.
  defp safe_return_to(target) when is_binary(target) do
    cond do
      target == "/" -> "/"
      same_origin_path?(target) -> target
      true -> ~p"/"
    end
  end

  defp safe_return_to(_), do: ~p"/"

  # A safe path: starts with a single `/`, no scheme/host, no
  # backslash, no whitespace, and either path or `/path?query` shape.
  defp same_origin_path?("/" <> rest) when byte_size(rest) > 0 do
    case String.first(rest) do
      "/" -> false
      "\\" -> false
      "\t" -> false
      "\n" -> false
      "\r" -> false
      " " -> false
      _ -> !String.contains?(rest, ["://", "\\", "\t", "\n", "\r"])
    end
  end

  defp same_origin_path?(_), do: false
end
