defmodule BeamwardenDaemonConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous_node = Beamwarden.AppIdentity.get_env(:daemon_node)
    previous_claw_node = System.get_env("CLAW_DAEMON_NODE")
    previous_claw_cookie = System.get_env("CLAW_DAEMON_COOKIE")
    previous_claw_mode = System.get_env("CLAW_DAEMON_NAME_MODE")
    previous_beamwarden_node = System.get_env("BEAMWARDEN_DAEMON_NODE")
    previous_beamwarden_cookie = System.get_env("BEAMWARDEN_DAEMON_COOKIE")
    previous_beamwarden_mode = System.get_env("BEAMWARDEN_DAEMON_NAME_MODE")
    previous_legacy_node = System.get_env("CLAW_DAEMON_NODE")
    previous_legacy_cookie = System.get_env("CLAW_DAEMON_COOKIE")
    previous_legacy_mode = System.get_env("CLAW_DAEMON_NAME_MODE")
    previous_future_node = Application.get_env(:beamwarden, :daemon_node)
    previous_future_cookie = Application.get_env(:beamwarden, :daemon_cookie)

    on_exit(fn ->
      if previous_node == nil do
        Beamwarden.AppIdentity.delete_env(:daemon_node)
      else
        Beamwarden.AppIdentity.put_env(:daemon_node, previous_node)
      end

      restore_env_var("CLAW_DAEMON_NODE", previous_claw_node)
      restore_env_var("CLAW_DAEMON_COOKIE", previous_claw_cookie)
      restore_env_var("CLAW_DAEMON_NAME_MODE", previous_claw_mode)
      restore_env_var("BEAMWARDEN_DAEMON_NODE", previous_beamwarden_node)
      restore_env_var("BEAMWARDEN_DAEMON_COOKIE", previous_beamwarden_cookie)
      restore_env_var("BEAMWARDEN_DAEMON_NAME_MODE", previous_beamwarden_mode)
      restore_env_var("CLAW_DAEMON_NODE", previous_legacy_node)
      restore_env_var("CLAW_DAEMON_COOKIE", previous_legacy_cookie)
      restore_env_var("CLAW_DAEMON_NAME_MODE", previous_legacy_mode)
      restore_app_env(:beamwarden, :daemon_node, previous_future_node)
      restore_app_env(:beamwarden, :daemon_cookie, previous_future_cookie)
    end)

    :ok
  end

  test "defaults to shortnames without daemon configuration" do
    Beamwarden.AppIdentity.delete_env(:daemon_node)
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")

    assert Beamwarden.Daemon.configured_name_mode() == :shortnames
  end

  test "uses longnames when the configured daemon host is fully qualified" do
    Beamwarden.AppIdentity.put_env(:daemon_node, "beamwarden_daemon@daemon.example.internal")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")

    assert Beamwarden.Daemon.configured_name_mode() == :longnames
  end

  test "environment override forces longnames" do
    Beamwarden.AppIdentity.put_env(:daemon_node, "beamwarden_daemon@daemon")
    System.put_env("BEAMWARDEN_DAEMON_NAME_MODE", "longnames")

    assert Beamwarden.Daemon.configured_name_mode() == :longnames
  end

  test "beamwarden env vars configure daemon runtime" do
    Beamwarden.AppIdentity.delete_env(:daemon_node)
    System.put_env("BEAMWARDEN_DAEMON_NODE", "beamwarden_daemon@new-host")
    System.put_env("BEAMWARDEN_DAEMON_COOKIE", "newcookie")
    System.put_env("BEAMWARDEN_DAEMON_NAME_MODE", "longnames")

    assert Beamwarden.Daemon.configured_node_label() == "beamwarden_daemon@new-host"
    assert Beamwarden.Daemon.daemon_cookie() == "newcookie"
    assert Beamwarden.Daemon.configured_name_mode() == :longnames
  end

  test "legacy claw env vars are ignored" do
    Beamwarden.AppIdentity.delete_env(:daemon_node)
    System.delete_env("BEAMWARDEN_DAEMON_NODE")
    System.delete_env("BEAMWARDEN_DAEMON_COOKIE")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")
    System.put_env("CLAW_DAEMON_NODE", "claw_code_daemon@legacy-host")
    System.put_env("CLAW_DAEMON_COOKIE", "legacycookie")
    System.put_env("CLAW_DAEMON_NAME_MODE", "longnames")

    assert Beamwarden.Daemon.configured_node_label() == nil
    assert Beamwarden.Daemon.daemon_cookie() == nil
    assert Beamwarden.Daemon.configured_name_mode() == :shortnames
  end

  test "future app env is visible through the compatibility helper" do
    Beamwarden.AppIdentity.delete_env(:daemon_node)
    Application.put_env(:beamwarden, :daemon_node, "beamwarden_daemon@app-env-host")

    assert Beamwarden.AppIdentity.get_env(:daemon_node) == "beamwarden_daemon@app-env-host"
    assert Beamwarden.Daemon.configured_node_label() == "beamwarden_daemon@app-env-host"
  end

  defp restore_env_var(name, nil), do: System.delete_env(name)
  defp restore_env_var(name, value), do: System.put_env(name, value)

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
