defmodule AshyWalnutDesk.Config.RuntimeSecurityTest do
  use ExUnit.Case, async: false

  @runtime_file Path.expand("../../../config/runtime.exs", __DIR__)

  test "prod + non-local PHX_HOST enables secure session flags and force_ssl" do
    config =
      with_env(
        %{
          "PHX_HOST" => "desk.example.com",
          "IDENTIFIER_HASH_SALT" => String.duplicate("a", 64),
          "ASH_AUTHENTICATION_SECRET" => String.duplicate("b", 64),
          "DATABASE_URL" => "ecto://user:pass@localhost/db",
          "SECRET_KEY_BASE" => String.duplicate("c", 64),
          "POOL_SIZE" => "10"
        },
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
        %{
          "PHX_HOST" => "localhost",
          "IDENTIFIER_HASH_SALT" => String.duplicate("a", 64),
          "ASH_AUTHENTICATION_SECRET" => String.duplicate("b", 64),
          "DATABASE_URL" => "ecto://user:pass@localhost/db",
          "SECRET_KEY_BASE" => String.duplicate("c", 64),
          "POOL_SIZE" => "10"
        },
        fn -> read_runtime_config(:prod) end
      )

    app_cfg = Keyword.fetch!(config, :ashy_walnut_desk)
    endpoint_cfg = Keyword.get(app_cfg, AshyWalnutDeskWeb.Endpoint, [])

    assert is_nil(Keyword.get(app_cfg, :session_options))
    refute Keyword.has_key?(endpoint_cfg, :force_ssl)
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
