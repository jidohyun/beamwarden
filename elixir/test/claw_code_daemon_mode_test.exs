defmodule ClawCodeDaemonModeTest do
  use ExUnit.Case, async: false

  setup do
    ensure_distributed_node!()

    daemon = start_peer!("claw_daemon_server")
    client_a = start_peer!("claw_daemon_client")
    client_b = start_peer!("claw_daemon_client")

    daemon_label = Atom.to_string(daemon.node)
    cookie = Atom.to_string(Node.get_cookie())

    configure_daemon!(daemon.node, daemon_label, cookie)
    configure_daemon!(client_a.node, daemon_label, cookie)
    configure_daemon!(client_b.node, daemon_label, cookie)

    assert {:ok, _status} = :rpc.call(daemon.node, ClawCode.Daemon, :start_server, [[]])

    on_exit(fn ->
      stop_peer(client_b)
      stop_peer(client_a)
      stop_peer(daemon)
    end)

    {:ok, daemon: daemon, client_a: client_a, client_b: client_b}
  end

  test "configured clients proxy the session lifecycle through the daemon node", %{
    daemon: daemon,
    client_a: client_a,
    client_b: client_b
  } do
    session_id = unique_id("daemon-proxy")
    on_exit(fn -> cleanup_remote_session(daemon.node, session_id) end)

    assert {:ok, daemon_status} =
             :rpc.call(client_a.node, ClawCode.CLI, :run, [["daemon-status"]])

    assert daemon_status =~ "role=client"
    assert daemon_status =~ "daemon_reachable=true"
    assert daemon_status =~ "configured_daemon_node=#{Atom.to_string(daemon.node)}"

    assert {:ok, server_status} = :rpc.call(daemon.node, ClawCode.CLI, :run, [["daemon-status"]])
    assert server_status =~ "role=server"

    assert {:ok, output} =
             :rpc.call(client_a.node, ClawCode.CLI, :run, [
               ["start-session", "--id", session_id, "review MCP tool"]
             ])

    assert output =~ "session_id=#{session_id}"
    assert output =~ "owner_node=#{Atom.to_string(daemon.node)}"

    assert :rpc.call(daemon.node, Registry, :lookup, [ClawCode.SessionRegistry, session_id]) != []

    assert :rpc.call(client_a.node, Registry, :lookup, [ClawCode.SessionRegistry, session_id]) ==
             []

    assert {:ok, status_output} =
             :rpc.call(client_b.node, ClawCode.CLI, :run, [["session-status", session_id]])

    assert status_output =~ "session_id=#{session_id}"
    assert status_output =~ "turns=1"
    assert status_output =~ "owner_node=#{Atom.to_string(daemon.node)}"
  end

  defp ensure_distributed_node! do
    System.cmd("epmd", ["-daemon"])

    if Node.alive?() do
      :ok
    else
      name = :"claw-daemon-mode-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp start_peer!(prefix) do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: String.to_atom("#{prefix}_#{System.unique_integer([:positive])}"),
        host: String.to_charlist(host_name())
      })

    assert :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])
    assert {:ok, _apps} = :rpc.call(peer_node, :application, :ensure_all_started, [:elixir])
    assert {:ok, _apps} = :rpc.call(peer_node, Application, :ensure_all_started, [:claw_code])
    %{peer: peer, node: peer_node}
  end

  defp configure_daemon!(target_node, daemon_label, cookie) do
    assert :ok =
             :rpc.call(target_node, Application, :put_env, [
               :claw_code,
               :daemon_node,
               daemon_label
             ])

    assert :ok =
             :rpc.call(target_node, Application, :put_env, [:claw_code, :daemon_cookie, cookie])
  end

  defp cleanup_remote_session(target_node, session_id) do
    case :rpc.call(target_node, Registry, :lookup, [ClawCode.SessionRegistry, session_id]) do
      [{_pid, _value}] -> :rpc.call(target_node, ClawCode.SessionServer, :stop, [session_id])
      [] -> :ok
      {:badrpc, _reason} -> :ok
    end

    File.rm(ClawCode.session_path(session_id))
  end

  defp stop_peer(%{peer: peer}) do
    :peer.stop(peer)
  catch
    :exit, _reason -> :ok
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp host_name do
    {:ok, hostname} = :inet.gethostname()
    List.to_string(hostname)
  end
end
