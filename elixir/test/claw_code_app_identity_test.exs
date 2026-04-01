defmodule ClawCodeAppIdentityTest do
  use ExUnit.Case, async: false

  setup do
    previous_runtime = Application.get_env(ClawCode.AppIdentity.runtime_app(), :daemon_node)
    previous_future = Application.get_env(ClawCode.AppIdentity.future_app(), :daemon_node)

    on_exit(fn ->
      restore_env(ClawCode.AppIdentity.runtime_app(), previous_runtime)
      restore_env(ClawCode.AppIdentity.future_app(), previous_future)
    end)

    ClawCode.AppIdentity.delete_env(:daemon_node)
    :ok
  end

  test "runtime app remains claw_code during the compatibility phase" do
    assert ClawCode.AppIdentity.runtime_app() == :claw_code
    assert :beamwarden in ClawCode.AppIdentity.config_apps()
  end

  test "compatibility helper prefers beamwarden config while falling back to runtime app" do
    assert ClawCode.AppIdentity.get_env(:daemon_node) == nil

    assert :ok = ClawCode.AppIdentity.put_env(:daemon_node, "claw_code_daemon@legacy-host")
    assert ClawCode.AppIdentity.get_env(:daemon_node) == "claw_code_daemon@legacy-host"

    assert :ok =
             Application.put_env(
               ClawCode.AppIdentity.future_app(),
               :daemon_node,
               "beamwarden_daemon@new-host"
             )

    assert ClawCode.AppIdentity.get_env(:daemon_node) == "beamwarden_daemon@new-host"

    assert :ok = ClawCode.AppIdentity.delete_env(:daemon_node)
    assert ClawCode.AppIdentity.get_env(:daemon_node) == nil
  end

  defp restore_env(app, nil), do: Application.delete_env(app, :daemon_node)
  defp restore_env(app, value), do: Application.put_env(app, :daemon_node, value)
end
