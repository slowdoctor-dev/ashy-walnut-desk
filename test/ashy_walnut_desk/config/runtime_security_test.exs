defmodule AshyWalnutDesk.Config.RuntimeSecurityTest do
  use ExUnit.Case, async: false

  @runtime_file Path.expand("../../../config/runtime.exs", __DIR__)

  test "prod + non-local PHX_HOST enables secure session flags and force_ssl" do
    config =
      with_env(
        Map.merge(twilio_env(), %{
          "PHX_HOST" => "desk.example.com",
          "IDENTIFIER_HASH_SALT" => String.duplicate("a", 64),
          "ASH_AUTHENTICATION_SECRET" => String.duplicate("b", 64),
          "DATABASE_URL" => "ecto://user:pass@localhost/db",
          "SECRET_KEY_BASE" => String.duplicate("c", 64),
          "POOL_SIZE" => "10",
          "ANTHROPIC_API_KEY" => "sk-ant-test",
          "EMBEDDING_ADAPTER" => "none"
        }),
        fn -> read_runtime_config(:prod) end
      )

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)

    assert Keyword.get(app_cfg, :session_options)[:secure] == true
    assert Keyword.get(app_cfg, :session_options)[:http_only] == true

    endpoint_cfg = Keyword.get(app_cfg, AshyWalnutDeskWeb.Endpoint)
    assert endpoint_cfg[:force_ssl] == [hsts: true]
  end

  test "prod + localhost PHX_HOST does not inject secure session flags or force_ssl" do
    config =
      with_env(
        Map.merge(twilio_env(), %{
          "PHX_HOST" => "localhost",
          "IDENTIFIER_HASH_SALT" => String.duplicate("a", 64),
          "ASH_AUTHENTICATION_SECRET" => String.duplicate("b", 64),
          "DATABASE_URL" => "ecto://user:pass@localhost/db",
          "SECRET_KEY_BASE" => String.duplicate("c", 64),
          "POOL_SIZE" => "10",
          "ANTHROPIC_API_KEY" => "sk-ant-test",
          "EMBEDDING_ADAPTER" => "none"
        }),
        fn -> read_runtime_config(:prod) end
      )

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)
    endpoint_cfg = Keyword.get(app_cfg, AshyWalnutDeskWeb.Endpoint, [])

    assert is_nil(Keyword.get(app_cfg, :session_options))
    refute Keyword.has_key?(endpoint_cfg, :force_ssl)
  end

  test "prod block stamps Twilio config from env" do
    config =
      with_env(base_prod_env(), fn -> read_runtime_config(:prod) end)

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)
    twilio = Keyword.fetch!(app_cfg, :twilio)
    assert twilio[:account_sid] == "AC_prod_test"
    assert twilio[:auth_token] == "prod_auth_token"
    assert twilio[:from_number] == "+15551112222"
    assert Keyword.fetch!(app_cfg, :twilio_signature_required) == true
  end

  test "prod boot raises when TWILIO_ACCOUNT_SID is missing" do
    base = base_prod_env(no_twilio: true)

    assert_raise RuntimeError, ~r/TWILIO_ACCOUNT_SID is missing/, fn ->
      with_env(base, fn -> read_runtime_config(:prod) end)
    end
  end

  test "prod boot raises when TWILIO_AUTH_TOKEN is missing" do
    base = Map.put(base_prod_env(no_twilio: true), "TWILIO_ACCOUNT_SID", "ACxx")

    assert_raise RuntimeError, ~r/TWILIO_AUTH_TOKEN is missing/, fn ->
      with_env(base, fn -> read_runtime_config(:prod) end)
    end
  end

  test "prod boot raises when TWILIO_FROM_NUMBER is missing" do
    base =
      base_prod_env(no_twilio: true)
      |> Map.put("TWILIO_ACCOUNT_SID", "ACxx")
      |> Map.put("TWILIO_AUTH_TOKEN", "tok")

    assert_raise RuntimeError, ~r/TWILIO_FROM_NUMBER is missing/, fn ->
      with_env(base, fn -> read_runtime_config(:prod) end)
    end
  end

  test "prod boot raises when EMBEDDING_ADAPTER is unset (ADR-026 explicit choice)" do
    base = Map.delete(base_prod_env(), "EMBEDDING_ADAPTER")

    assert_raise RuntimeError, ~r/EMBEDDING_ADAPTER/, fn ->
      with_env(base, fn -> read_runtime_config(:prod) end)
    end
  end

  test "prod EMBEDDING_ADAPTER=voyage requires VOYAGE_API_KEY, then stamps config" do
    base = Map.put(base_prod_env(), "EMBEDDING_ADAPTER", "voyage")

    assert_raise RuntimeError, ~r/VOYAGE_API_KEY/, fn ->
      with_env(base, fn -> read_runtime_config(:prod) end)
    end

    config =
      with_env(Map.put(base, "VOYAGE_API_KEY", "pa-test"), fn ->
        read_runtime_config(:prod)
      end)

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)
    assert Keyword.fetch!(app_cfg, :voyage)[:api_key] == "pa-test"

    assert Keyword.fetch!(app_cfg, :embedding_adapter) ==
             AshyWalnutDesk.Knowledge.Embedders.Voyage
  end

  test "prod EMBEDDING_ADAPTER=none disables the external embedder" do
    config = with_env(base_prod_env(), fn -> read_runtime_config(:prod) end)

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)
    assert Keyword.has_key?(app_cfg, :embedding_adapter)
    assert Keyword.fetch!(app_cfg, :embedding_adapter) == nil
  end

  defp twilio_env do
    %{
      "TWILIO_ACCOUNT_SID" => "AC_prod_test",
      "TWILIO_AUTH_TOKEN" => "prod_auth_token",
      "TWILIO_FROM_NUMBER" => "+15551112222"
    }
  end

  defp base_prod_env(opts \\ []) do
    base = %{
      "PHX_HOST" => "localhost",
      "IDENTIFIER_HASH_SALT" => String.duplicate("a", 64),
      "ASH_AUTHENTICATION_SECRET" => String.duplicate("b", 64),
      "DATABASE_URL" => "ecto://user:pass@localhost/db",
      "SECRET_KEY_BASE" => String.duplicate("c", 64),
      "POOL_SIZE" => "10",
      "ANTHROPIC_API_KEY" => "sk-ant-test",
      "EMBEDDING_ADAPTER" => "none"
    }

    if Keyword.get(opts, :no_twilio), do: base, else: Map.merge(base, twilio_env())
  end

  defp read_runtime_config(env) do
    {config, _imports} = Config.Reader.read_imports!(@runtime_file, env: env)
    config
  end

  defp with_env(new_env, fun) do
    old_env = Map.new(new_env, fn {k, _} -> {k, System.get_env(k)} end)

    try do
      Enum.each(new_env, fn {k, v} -> System.put_env(k, v) end)
      fun.()
    after
      Enum.each(old_env, fn {k, v} ->
        if is_nil(v), do: System.delete_env(k), else: System.put_env(k, v)
      end)
    end
  end
end
