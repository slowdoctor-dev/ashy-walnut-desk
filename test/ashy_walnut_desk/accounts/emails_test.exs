defmodule AshyWalnutDesk.Accounts.EmailsTest do
  use ExUnit.Case, async: false
  import Swoosh.TestAssertions

  alias AshyWalnutDesk.Accounts.Emails

  test "deliver_magic_link escapes email and url in html body" do
    malicious_email = ~s|attacker@example.com"><img src=x onerror=alert(1)>|
    malicious_url = ~s|https://example.test/magic"><script>alert('x')</script>|

    assert {:ok, _meta} = Emails.deliver_magic_link(malicious_email, malicious_url)

    assert_email_sent(fn message ->
      to_match? = Enum.any?(message.to, fn {_, addr} -> addr == malicious_email end)

      to_match? and
        not String.contains?(message.html_body, malicious_email) and
        not String.contains?(message.html_body, malicious_url) and
        String.contains?(
          message.html_body,
          "attacker@example.com&quot;&gt;&lt;img src=x onerror=alert(1)&gt;"
        ) and
        String.contains?(
          message.html_body,
          "https://example.test/magic&quot;&gt;&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"
        )
    end)
  end
end
