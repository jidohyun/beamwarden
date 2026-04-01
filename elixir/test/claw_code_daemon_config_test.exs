defmodule ClawCodeDaemonConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous_node = Application.get_env(:claw_code, :daemon_node)
    previous_mode = System.get_env("CLAW_DAEMON_NAME_MODE")
    previous_beamwarden_node = System.get_env("BEAMWARDEN_DAEMON_NODE")
    previous_beamwarden_cookie = System.get_env("BEAMWARDEN_DAEMON_COOKIE")
    previous_beamwarden_mode = System.get_env("BEAMWARDEN_DAEMON_NAME_MODE")

    on_exit(fn ->
      if previous_node == nil do
        Application.delete_env(:claw_code, :daemon_node)
      else
        Application.put_env(:claw_code, :daemon_node, previous_node)
      end

      restore_env_var("BEAMWARDEN_DAEMON_NODE", previous_beamwarden_node)
      restore_env_var("BEAMWARDEN_DAEMON_COOKIE", previous_beamwarden_cookie)
      restore_env_var("BEAMWARDEN_DAEMON_NAME_MODE", previous_beamwarden_mode)

      if previous_mode == nil do
        System.delete_env("CLAW_DAEMON_NAME_MODE")
      else
        System.put_env("CLAW_DAEMON_NAME_MODE", previous_mode)
      end
    end)

    :ok
  end

  test "defaults to shortnames without daemon configuration" do
    Application.delete_env(:claw_code, :daemon_node)
    System.delete_env("CLAW_DAEMON_NAME_MODE")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")

    assert ClawCode.Daemon.configured_name_mode() == :shortnames
  end

  test "uses longnames when the configured daemon host is fully qualified" do
    Application.put_env(:claw_code, :daemon_node, "claw_code_daemon@daemon.example.internal")
    System.delete_env("CLAW_DAEMON_NAME_MODE")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")

    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end

  test "environment override forces longnames" do
    Application.put_env(:claw_code, :daemon_node, "claw_code_daemon@daemon")
    System.put_env("CLAW_DAEMON_NAME_MODE", "longnames")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")

    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end

  test "beamwarden env vars take precedence over claw compatibility vars" do
    Application.delete_env(:claw_code, :daemon_node)
    System.put_env("CLAW_DAEMON_NODE", "claw_code_daemon@legacy-host")
    System.put_env("BEAMWARDEN_DAEMON_NODE", "beamwarden_daemon@new-host")
    System.put_env("CLAW_DAEMON_COOKIE", "legacycookie")
    System.put_env("BEAMWARDEN_DAEMON_COOKIE", "newcookie")
    System.put_env("CLAW_DAEMON_NAME_MODE", "shortnames")
    System.put_env("BEAMWARDEN_DAEMON_NAME_MODE", "longnames")

    assert ClawCode.Daemon.configured_node_label() == "beamwarden_daemon@new-host"
    assert ClawCode.Daemon.daemon_cookie() == "newcookie"
    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end

  test "beamwarden env vars fall back to claw compatibility vars when absent" do
    Application.delete_env(:claw_code, :daemon_node)
    System.delete_env("BEAMWARDEN_DAEMON_NODE")
    System.delete_env("BEAMWARDEN_DAEMON_COOKIE")
    System.delete_env("BEAMWARDEN_DAEMON_NAME_MODE")
    System.put_env("CLAW_DAEMON_NODE", "claw_code_daemon@legacy-host")
    System.put_env("CLAW_DAEMON_COOKIE", "legacycookie")
    System.put_env("CLAW_DAEMON_NAME_MODE", "longnames")

    assert ClawCode.Daemon.configured_node_label() == "claw_code_daemon@legacy-host"
    assert ClawCode.Daemon.daemon_cookie() == "legacycookie"
    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end

  defp restore_env_var(name, nil), do: System.delete_env(name)
  defp restore_env_var(name, value), do: System.put_env(name, value)
end
