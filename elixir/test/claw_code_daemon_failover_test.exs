defmodule ClawCodeDaemonFailoverTest do
  use ExUnit.Case, async: false

  setup do
    ensure_distributed_node!()
    :ok
  end

  test "configured but unreachable daemon falls back to local session execution" do
    session_id = unique_id("daemon-fallback")
    unreachable_daemon = "ghost@#{host_name()}"
    original_daemon_node = ClawCode.AppIdentity.get_env(:daemon_node)
    original_cookie = ClawCode.AppIdentity.get_env(:daemon_cookie)

    on_exit(fn ->
      restore_env(:daemon_node, original_daemon_node)
      restore_env(:daemon_cookie, original_cookie)
      cleanup_local_session(session_id)
    end)

    assert :ok = ClawCode.AppIdentity.put_env(:daemon_node, unreachable_daemon)

    assert :ok =
             ClawCode.AppIdentity.put_env(:daemon_cookie, Atom.to_string(Node.get_cookie()))

    assert {:ok, status_output} = ClawCode.CLI.run(["daemon-status"])
    assert status_output =~ "role=standalone"
    assert status_output =~ "configured_daemon_node=#{unreachable_daemon}"
    assert status_output =~ "daemon_reachable=false"

    assert {:ok, output} =
             ClawCode.CLI.run(["start-session", "--id", session_id, "review MCP tool"])

    assert output =~ "session_id=#{session_id}"
    assert output =~ "owner_node=#{Atom.to_string(node())}"
    assert output =~ "turns=1"
    assert Registry.lookup(ClawCode.SessionRegistry, session_id) != []
  end

  defp ensure_distributed_node! do
    System.cmd("epmd", ["-daemon"])

    if Node.alive?() do
      :ok
    else
      name = :"claw-daemon-fallback-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp cleanup_local_session(session_id) do
    if Registry.lookup(ClawCode.SessionRegistry, session_id) != [] do
      ClawCode.SessionServer.stop(session_id)
    end

    File.rm(ClawCode.session_path(session_id))
  end

  defp restore_env(key, nil), do: ClawCode.AppIdentity.delete_env(key)
  defp restore_env(key, value), do: ClawCode.AppIdentity.put_env(key, value)

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp host_name do
    {:ok, hostname} = :inet.gethostname()
    List.to_string(hostname)
  end
end
