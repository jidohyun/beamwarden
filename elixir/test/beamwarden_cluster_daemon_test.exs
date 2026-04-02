defmodule BeamwardenClusterDaemonTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    ensure_distributed_node!()
    :ok
  end

  test "cluster daemon ledger survives restart without requiring session json" do
    session_id = unique_id("daemon-ledger")
    on_exit(fn -> cleanup_local_session(session_id) end)

    {:ok, _pid} = Beamwarden.ControlPlane.ensure_session(session_id)
    assert %{owner_node: owner_node} = Beamwarden.ClusterDaemon.local_record(:session, session_id)
    assert owner_node == Beamwarden.Cluster.local_owner_label()

    File.rm(Beamwarden.session_path(session_id))

    daemon_pid = Process.whereis(Beamwarden.ClusterDaemon)
    assert is_pid(daemon_pid)
    ref = Process.monitor(daemon_pid)

    assert :ok =
             Supervisor.terminate_child(Beamwarden.ClusterSupervisor, Beamwarden.ClusterDaemon)

    assert_receive {:DOWN, ^ref, :process, ^daemon_pid, _reason}, 5_000

    assert {:ok, _pid} =
             Supervisor.restart_child(Beamwarden.ClusterSupervisor, Beamwarden.ClusterDaemon)

    wait_until(fn -> match?(%{}, Beamwarden.ClusterDaemon.local_record(:session, session_id)) end)

    assert %{identifier: ^session_id, owner_node: ^owner_node} =
             Beamwarden.ClusterDaemon.local_record(:session, session_id)

    status_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cluster-status"])
      end)

    assert status_output =~ "daemon_mode=supervised DETS-backed ownership ledger"
    assert status_output =~ "daemon_records="
  end

  test "session failover reclaims ownership from an unreachable peer using the daemon ledger" do
    peer = start_peer!()
    peer_node = peer.node
    session_id = routed_identifier(:session, peer_node)

    on_exit(fn ->
      cleanup_local_session(session_id)
      stop_peer(peer)
    end)

    {:ok, first_snapshot} = Beamwarden.ControlPlane.submit_prompt(session_id, "review MCP tool")
    assert first_snapshot.owner_node == Atom.to_string(peer_node)

    assert %{owner_node: owner_before, epoch: epoch_before} =
             Beamwarden.ClusterDaemon.local_record(:session, session_id)

    assert owner_before == Atom.to_string(peer_node)

    stop_peer(peer)
    wait_until(fn -> peer_node not in Node.list() end)

    {:ok, second_snapshot} =
      Beamwarden.ControlPlane.submit_prompt(session_id, "review MCP tool again")

    assert second_snapshot.owner_node == Atom.to_string(node())
    assert second_snapshot.turns == 2

    assert %{owner_node: owner_after, epoch: epoch_after} =
             Beamwarden.ClusterDaemon.local_record(:session, session_id)

    assert owner_after == Atom.to_string(node())
    assert epoch_after > epoch_before
  end

  test "workflow failover reclaims ownership from an unreachable peer using the daemon ledger" do
    peer = start_peer!()
    peer_node = peer.node
    workflow_id = routed_identifier(:workflow, peer_node)

    on_exit(fn ->
      cleanup_local_workflow(workflow_id)
      stop_peer(peer)
    end)

    assert {:ok, first_snapshot} =
             Beamwarden.ControlPlane.add_workflow_step(
               workflow_id,
               "heal cluster",
               "before failover"
             )

    assert first_snapshot.owner_node == Atom.to_string(peer_node)

    assert %{owner_node: owner_before, epoch: epoch_before} =
             Beamwarden.ClusterDaemon.local_record(:workflow, workflow_id)

    assert owner_before == Atom.to_string(peer_node)

    stop_peer(peer)
    wait_until(fn -> peer_node not in Node.list() end)

    assert {:ok, second_snapshot} =
             Beamwarden.ControlPlane.complete_workflow_step(workflow_id, "1")

    assert second_snapshot.owner_node == Atom.to_string(node())
    assert [%{"status" => "completed", "title" => "heal cluster"}] = second_snapshot.steps

    assert %{owner_node: owner_after, epoch: epoch_after} =
             Beamwarden.ClusterDaemon.local_record(:workflow, workflow_id)

    assert owner_after == Atom.to_string(node())
    assert epoch_after > epoch_before
  end

  defp ensure_distributed_node! do
    System.cmd("epmd", ["-daemon"])

    if Node.alive?() do
      :ok
    else
      name = :"beamwarden-daemon-test-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp start_peer! do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: String.to_atom("beamwarden_daemon_peer_#{System.unique_integer([:positive])}"),
        host: String.to_charlist(host_name()),
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie())]
      })

    true = Node.connect(peer_node)
    assert :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])
    assert :ok = :rpc.call(peer_node, Beamwarden.AppIdentity, :ensure_started, [])
    %{peer: peer, node: peer_node}
  end

  defp stop_peer(%{peer: peer}) do
    :peer.stop(peer)
  catch
    :exit, _reason -> :ok
  end

  defp routed_identifier(scope, expected_node) do
    Stream.repeatedly(fn ->
      suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      "#{scope}-#{suffix}"
    end)
    |> Enum.find(fn identifier ->
      Beamwarden.Cluster.owner_node(scope, identifier) == expected_node
    end)
  end

  defp cleanup_local_session(session_id) do
    if Registry.lookup(Beamwarden.SessionRegistry, session_id) != [] do
      Beamwarden.SessionServer.stop(session_id)
    end

    File.rm(Beamwarden.session_path(session_id))
  end

  defp cleanup_local_workflow(workflow_id) do
    if Registry.lookup(Beamwarden.WorkflowRegistry, workflow_id) != [] do
      Beamwarden.WorkflowServer.stop(workflow_id)
    end

    File.rm(Beamwarden.workflow_path(workflow_id))
  end

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(fun, attempts) do
    cond do
      fun.() ->
        :ok

      attempts <= 0 ->
        flunk("condition did not become true before retries were exhausted")

      true ->
        Process.sleep(100)
        wait_until(fun, attempts - 1)
    end
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
