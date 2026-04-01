defmodule BeamwardenAppIdentityTest do
  use ExUnit.Case, async: false

  setup do
    previous_runtime = Application.get_env(Beamwarden.AppIdentity.runtime_app(), :daemon_node)
    previous_legacy = Application.get_env(Beamwarden.AppIdentity.legacy_app(), :daemon_node)

    on_exit(fn ->
      restore_env(Beamwarden.AppIdentity.runtime_app(), previous_runtime)
      restore_env(Beamwarden.AppIdentity.legacy_app(), previous_legacy)
    end)

    Beamwarden.AppIdentity.delete_env(:daemon_node)
    :ok
  end

  test "runtime app is beamwarden while claw_code remains a legacy fallback" do
    assert Beamwarden.AppIdentity.runtime_app() == :beamwarden
    assert Beamwarden.AppIdentity.legacy_app() == :claw_code
  end

  test "compatibility helper prefers beamwarden config while falling back to claw_code" do
    assert Beamwarden.AppIdentity.get_env(:daemon_node) == nil

    assert :ok =
             Application.put_env(
               Beamwarden.AppIdentity.legacy_app(),
               :daemon_node,
               "claw_code_daemon@legacy-host"
             )

    assert Beamwarden.AppIdentity.get_env(:daemon_node) == "claw_code_daemon@legacy-host"

    assert :ok =
             Application.put_env(
               Beamwarden.AppIdentity.runtime_app(),
               :daemon_node,
               "beamwarden_daemon@new-host"
             )

    assert Beamwarden.AppIdentity.get_env(:daemon_node) == "beamwarden_daemon@new-host"

    assert :ok = Beamwarden.AppIdentity.delete_env(:daemon_node)
    assert Beamwarden.AppIdentity.get_env(:daemon_node) == nil
  end

  defp restore_env(app, nil), do: Application.delete_env(app, :daemon_node)
  defp restore_env(app, value), do: Application.put_env(app, :daemon_node, value)
end
