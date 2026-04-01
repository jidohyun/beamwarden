defmodule ClawCodeDaemonConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous_node = Application.get_env(:claw_code, :daemon_node)
    previous_mode = System.get_env("CLAW_DAEMON_NAME_MODE")

    on_exit(fn ->
      if previous_node == nil do
        Application.delete_env(:claw_code, :daemon_node)
      else
        Application.put_env(:claw_code, :daemon_node, previous_node)
      end

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

    assert ClawCode.Daemon.configured_name_mode() == :shortnames
  end

  test "uses longnames when the configured daemon host is fully qualified" do
    Application.put_env(:claw_code, :daemon_node, "claw_code_daemon@daemon.example.internal")
    System.delete_env("CLAW_DAEMON_NAME_MODE")

    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end

  test "environment override forces longnames" do
    Application.put_env(:claw_code, :daemon_node, "claw_code_daemon@daemon")
    System.put_env("CLAW_DAEMON_NAME_MODE", "longnames")

    assert ClawCode.Daemon.configured_name_mode() == :longnames
  end
end
