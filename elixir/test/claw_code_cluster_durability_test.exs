defmodule ClawCodeClusterDurabilityTest do
  use ExUnit.Case, async: false

  setup_all do
    ensure_distributed_node!()
    peer = start_peer!()

    on_exit(fn ->
      stop_peer(peer)
    end)

    {:ok, peer: peer}
  end

  test "running session owner beats stale persisted owner metadata", %{peer: %{node: peer_node}} do
    session_id = unique_id("running-owner")
    on_exit(fn -> cleanup_session(session_id, peer_node) end)

    assert {:ok, _pid} =
             :rpc.call(peer_node, ClawCode.ControlPlane, :ensure_local_session, [session_id])

    assert {:ok, remote_snapshot} =
             :rpc.call(peer_node, ClawCode.ControlPlane, :submit_prompt_local, [
               session_id,
               "review MCP tool"
             ])

    assert remote_snapshot.owner_node == Atom.to_string(peer_node)

    rewrite_owner_node!(ClawCode.session_path(session_id), Atom.to_string(node()))

    assert ClawCode.ControlPlane.session_route_node(session_id) == peer_node

    assert {:ok, snapshot} =
             ClawCode.ControlPlane.submit_prompt(session_id, "review tool execution")

    assert snapshot.owner_node == Atom.to_string(peer_node)
    assert snapshot.turns == 2
    assert Registry.lookup(ClawCode.SessionRegistry, session_id) == []

    remote_lookup =
      :rpc.call(peer_node, Registry, :lookup, [ClawCode.SessionRegistry, session_id])

    assert remote_lookup != []
  end

  test "unreachable persisted workflow owner falls back to the reachable cluster member", %{
    peer: %{node: peer_node}
  } do
    workflow_id = unique_id("workflow-failover")
    on_exit(fn -> cleanup_workflow(workflow_id, peer_node) end)

    ClawCode.WorkflowStore.save(%{
      workflow_id: workflow_id,
      steps: [],
      owner_node: "ghost@host"
    })

    expected_target = ClawCode.Cluster.owner_node(:workflow, workflow_id)

    assert expected_target in ClawCode.Cluster.member_nodes()
    assert ClawCode.ControlPlane.workflow_route_node(workflow_id) == expected_target

    assert {:ok, snapshot} =
             ClawCode.ControlPlane.add_workflow_step(workflow_id, "heal cluster", "fail over")

    assert snapshot.owner_node == Atom.to_string(expected_target)

    assert [%{"title" => "heal cluster", "description" => "fail over", "status" => "pending"}] =
             snapshot.steps

    assert_running_on_target!(expected_target, ClawCode.WorkflowRegistry, workflow_id, peer_node)
  end

  test "local session state rehydrates after the session server crashes without session json", %{
    peer: %{node: peer_node}
  } do
    session_id = unique_id("session-restart")
    on_exit(fn -> cleanup_session(session_id, peer_node) end)

    assert {:ok, first_snapshot} =
             ClawCode.ControlPlane.submit_prompt_local(session_id, "review MCP tool")

    assert first_snapshot.turns == 1
    assert pid = lookup_pid(ClawCode.SessionRegistry, session_id)
    File.rm!(ClawCode.session_path(session_id))

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    restarted_pid = wait_for_restarted_pid(ClawCode.SessionRegistry, session_id, pid)
    assert restarted_pid != pid

    assert {:ok, second_snapshot} = ClawCode.ControlPlane.session_snapshot_local(session_id)
    assert second_snapshot.turns == 1

    assert {:ok, third_snapshot} =
             ClawCode.ControlPlane.submit_prompt_local(session_id, "review tool execution")

    assert third_snapshot.turns == 2
  end

  test "local workflow state rehydrates after the workflow server crashes without workflow json",
       %{
         peer: %{node: peer_node}
       } do
    workflow_id = unique_id("workflow-restart")
    on_exit(fn -> cleanup_workflow(workflow_id, peer_node) end)

    assert {:ok, first_snapshot} =
             ClawCode.ControlPlane.add_workflow_step_local(workflow_id, "bootstrap session")

    assert [%{"title" => "bootstrap session", "status" => "pending"}] = first_snapshot.steps
    assert pid = lookup_pid(ClawCode.WorkflowRegistry, workflow_id)
    File.rm!(ClawCode.workflow_path(workflow_id))

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    restarted_pid = wait_for_restarted_pid(ClawCode.WorkflowRegistry, workflow_id, pid)
    assert restarted_pid != pid

    assert {:ok, second_snapshot} = ClawCode.ControlPlane.workflow_snapshot_local(workflow_id)
    assert [%{"title" => "bootstrap session", "status" => "pending"}] = second_snapshot.steps

    assert {:ok, third_snapshot} =
             ClawCode.ControlPlane.complete_workflow_step_local(workflow_id, "1")

    assert [%{"title" => "bootstrap session", "status" => "completed"}] = third_snapshot.steps
  end

  defp ensure_distributed_node! do
    System.cmd("epmd", ["-daemon"])

    if Node.alive?() do
      :ok
    else
      name = :"claw-durability-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp start_peer! do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: String.to_atom("claw_peer_#{System.unique_integer([:positive])}"),
        host: String.to_charlist(host_name()),
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie())]
      })

    assert :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])
    assert {:ok, _apps} = :rpc.call(peer_node, :application, :ensure_all_started, [:elixir])
    assert :ok = :rpc.call(peer_node, ClawCode.AppIdentity, :ensure_started, [])

    %{peer: peer, node: peer_node}
  end

  defp stop_peer(%{peer: peer}) do
    :peer.stop(peer)
  catch
    :exit, _reason -> :ok
  end

  defp cleanup_session(session_id, peer_node) do
    if Registry.lookup(ClawCode.SessionRegistry, session_id) != [] do
      ClawCode.SessionServer.stop(session_id)
    end

    if :rpc.call(peer_node, Registry, :lookup, [ClawCode.SessionRegistry, session_id]) != [] do
      :rpc.call(peer_node, ClawCode.SessionServer, :stop, [session_id])
    end

    File.rm(ClawCode.session_path(session_id))
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

  defp rewrite_owner_node!(path, owner_node) do
    payload =
      path
      |> File.read!()
      |> JSON.decode!()
      |> Map.put("owner_node", owner_node)

    File.write!(path, JSON.encode!(payload))
  end

  defp assert_running_on_target!(expected_target, registry, identifier, peer_node) do
    if expected_target == node() do
      assert lookup_pid(registry, identifier)
      assert :rpc.call(peer_node, Registry, :lookup, [registry, identifier]) == []
    else
      assert Registry.lookup(registry, identifier) == []
      assert :rpc.call(peer_node, Registry, :lookup, [registry, identifier]) != []
    end
  end

  defp lookup_pid(registry, identifier) do
    case Registry.lookup(registry, identifier) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp wait_for_restarted_pid(registry, identifier, previous_pid, attempts \\ 20)

  defp wait_for_restarted_pid(_registry, _identifier, previous_pid, 0) do
    flunk("expected #{inspect(previous_pid)} to restart under the registry")
  end

  defp wait_for_restarted_pid(registry, identifier, previous_pid, attempts) do
    case lookup_pid(registry, identifier) do
      nil ->
        Process.sleep(25)
        wait_for_restarted_pid(registry, identifier, previous_pid, attempts - 1)

      ^previous_pid ->
        Process.sleep(25)
        wait_for_restarted_pid(registry, identifier, previous_pid, attempts - 1)

      pid ->
        pid
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
