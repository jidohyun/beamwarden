defmodule ClawCodeClusterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup_all do
    ensure_distributed_node!()

    peer_name = :peer.random_name(~c"claw_peer")
    peer_args = [~c"-setcookie", Atom.to_charlist(Node.get_cookie()), ~c"-pa" | :code.get_path()]

    {:ok, peer, peer_node} = :peer.start_link(%{name: peer_name, args: peer_args})
    true = Node.connect(peer_node)
    :ok = ensure_peer_started(peer_node)

    on_exit(fn ->
      if is_pid(peer) and Process.alive?(peer) do
        try do
          :peer.stop(peer)
        catch
          :exit, _reason -> :ok
        end
      else
        :ok
      end
    end)

    %{peer: peer, peer_node: peer_node}
  end

  test "session routing can target a connected peer node", %{peer_node: peer_node} do
    session_id = routed_identifier(:session, peer_node)
    on_exit(fn -> cleanup_session(session_id, peer_node) end)

    {:ok, snapshot} = ClawCode.ControlPlane.submit_prompt(session_id, "review MCP tool")

    assert snapshot.owner_node == Atom.to_string(peer_node)
    assert Registry.lookup(ClawCode.SessionRegistry, session_id) == []

    remote_lookup =
      :rpc.call(peer_node, Registry, :lookup, [ClawCode.SessionRegistry, session_id])

    assert remote_lookup != []

    status_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["control-plane-status"])
      end)

    assert status_output =~ "Cluster members:"
    assert status_output =~ session_id
    assert status_output =~ Atom.to_string(peer_node)
  end

  test "workflow routing and cluster cli reflect connected nodes", %{peer_node: peer_node} do
    workflow_id = routed_identifier(:workflow, peer_node)
    on_exit(fn -> cleanup_workflow(workflow_id, peer_node) end)

    {:ok, started} = ClawCode.ControlPlane.start_workflow(workflow_id, ["ship docs"])
    {:ok, advanced} = ClawCode.ControlPlane.advance_task(workflow_id, "1", "completed", "done")

    assert started.owner_node == Atom.to_string(peer_node)
    assert advanced.owner_node == Atom.to_string(peer_node)
    assert Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) == []

    remote_lookup =
      :rpc.call(peer_node, Registry, :lookup, [ClawCode.WorkflowRegistry, workflow_id])

    assert remote_lookup != []

    cluster_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["cluster-status"])
      end)

    connect_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["cluster-connect", Atom.to_string(peer_node)])
      end)

    assert cluster_output =~ "distributed=true"
    assert cluster_output =~ Atom.to_string(peer_node)
    assert connect_output =~ "Cluster Connect"
    assert connect_output =~ Atom.to_string(peer_node)
  end

  defp ensure_distributed_node! do
    System.cmd("epmd", ["-daemon"])

    if Node.alive?() do
      :ok
    else
      name = :"claw-test-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp ensure_peer_started(peer_node) do
    case :rpc.call(peer_node, ClawCode.AppIdentity, :ensure_started, []) do
      :ok -> :ok
      {:badrpc, reason} -> raise "failed to start claw_code on #{peer_node}: #{inspect(reason)}"
      other -> raise "unexpected peer start result: #{inspect(other)}"
    end
  end

  defp routed_identifier(scope, expected_node) do
    Stream.repeatedly(fn ->
      suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      "#{scope}-#{suffix}"
    end)
    |> Enum.find(fn identifier ->
      ClawCode.Cluster.owner_node(scope, identifier) == expected_node
    end)
  end

  defp cleanup_session(session_id, peer_node) do
    if Registry.lookup(ClawCode.SessionRegistry, session_id) != [] do
      ClawCode.SessionServer.stop(session_id)
    end

    if :rpc.call(peer_node, Registry, :lookup, [ClawCode.SessionRegistry, session_id]) != [] do
      :rpc.call(peer_node, ClawCode.SessionServer, :stop, [session_id])
    end

    File.rm(Path.join(ClawCode.session_root(), "#{session_id}.json"))
  end

  defp cleanup_workflow(workflow_id, peer_node) do
    if Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) != [] do
      ClawCode.WorkflowServer.stop(workflow_id)
    end

    if :rpc.call(peer_node, Registry, :lookup, [ClawCode.WorkflowRegistry, workflow_id]) != [] do
      :rpc.call(peer_node, ClawCode.WorkflowServer, :stop, [workflow_id])
    end

    File.rm(ClawCode.workflow_path(workflow_id))
  end
end
