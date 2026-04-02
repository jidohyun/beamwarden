defmodule BeamwardenAppIdentityTest do
  use ExUnit.Case, async: false

  setup do
    previous_runtime = Application.get_env(Beamwarden.AppIdentity.runtime_app(), :daemon_node)

    on_exit(fn ->
      restore_env(Beamwarden.AppIdentity.runtime_app(), previous_runtime)
    end)

    Beamwarden.AppIdentity.delete_env(:daemon_node)
    :ok
  end

  test "runtime app stays beamwarden" do
    assert Beamwarden.AppIdentity.runtime_app() == :beamwarden
  end

  test "app identity helper reads and clears beamwarden runtime config" do
    assert Beamwarden.AppIdentity.get_env(:daemon_node) == nil

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
