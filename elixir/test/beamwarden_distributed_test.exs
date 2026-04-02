defmodule BeamwardenDistributedTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    ensure_local_distribution!()
    peer = start_peer!()
    on_exit(fn -> stop_peer(peer) end)
    {:ok, peer: peer}
  end

  test "peer node can bootstrap beamwarden and run control-plane status", %{
    peer: %{node: peer_node}
  } do
    assert {:ok, output} = :rpc.call(peer_node, Beamwarden.CLI, :run, [["control-plane-status"]])
    assert output =~ "# OTP Control Plane"
    assert output =~ "Cluster mode: distributed"
    assert output =~ "Cluster members:"
  end

  test "remote session lifecycle stays isolated from local registries", %{
    peer: %{node: peer_node}
  } do
    session_id = unique_id("remote-session")
    on_exit(fn -> cleanup_remote_session(peer_node, session_id) end)

    assert {:ok, _pid} =
             :rpc.call(peer_node, Beamwarden.ControlPlane, :ensure_session, [session_id])

    assert {:ok, snapshot} =
             :rpc.call(peer_node, Beamwarden.ControlPlane, :submit_prompt, [
               session_id,
               "review MCP tool"
             ])

    assert snapshot.session_id == session_id
    assert snapshot.turns == 1

    assert {:ok, session_output} =
             :rpc.call(peer_node, Beamwarden.CLI, :run, [["session-status", session_id]])

    assert session_output =~ "session_id=#{session_id}"
    assert session_output =~ "turns=1"

    assert {:ok, remote_status} =
             :rpc.call(peer_node, Beamwarden.CLI, :run, [["control-plane-status"]])

    assert remote_status =~ "session=#{session_id}"

    local_status = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["control-plane-status"]) end)
    assert local_status =~ session_id

    assert File.exists?(Path.join(Beamwarden.session_root(), "#{session_id}.json"))
  end

  test "remote workflow lifecycle stays isolated from local registries", %{
    peer: %{node: peer_node}
  } do
    workflow_id = unique_id("remote-workflow")
    on_exit(fn -> cleanup_remote_workflow(peer_node, workflow_id) end)

    assert {:ok, snapshot} =
             :rpc.call(peer_node, Beamwarden.ControlPlane, :start_workflow, [workflow_id, []])

    assert snapshot.workflow_id == workflow_id

    assert {:ok, updated} =
             :rpc.call(peer_node, Beamwarden.ControlPlane, :add_workflow_step, [
               workflow_id,
               "bootstrap session"
             ])

    assert [%{"title" => "bootstrap session", "status" => "pending"}] = updated.steps

    assert {:ok, completed} =
             :rpc.call(peer_node, Beamwarden.ControlPlane, :complete_workflow_step, [
               workflow_id,
               "1"
             ])

    assert [%{"status" => "completed"}] = completed.steps

    assert {:ok, workflow_output} =
             :rpc.call(peer_node, Beamwarden.CLI, :run, [["workflow-status", workflow_id]])

    assert workflow_output =~ "workflow_id=#{workflow_id}"
    assert workflow_output =~ "[completed] 1 — bootstrap session"

    assert {:ok, remote_status} =
             :rpc.call(peer_node, Beamwarden.CLI, :run, [["control-plane-status"]])

    assert remote_status =~ "workflow=#{workflow_id}"

    local_status = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["control-plane-status"]) end)
    assert local_status =~ workflow_id

    assert File.exists?(Beamwarden.workflow_path(workflow_id))
  end

  defp ensure_local_distribution! do
    if Node.alive?() do
      :ok
    else
      System.cmd("epmd", ["-daemon"])
      host = host_name()
      name = String.to_atom("beamwarden_test_#{System.unique_integer([:positive])}@#{host}")
      assert {:ok, _pid} = Node.start(name, :shortnames)
      :ok
    end
  end

  defp start_peer! do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: String.to_atom("beamwarden_peer_#{System.unique_integer([:positive])}"),
        host: String.to_charlist(host_name()),
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie())]
      })

    assert :ok = :rpc.call(peer_node, :code, :add_paths, [:code.get_path()])
    assert {:ok, _apps} = :rpc.call(peer_node, :application, :ensure_all_started, [:elixir])
    assert :ok = :rpc.call(peer_node, Beamwarden.AppIdentity, :ensure_started, [])

    %{peer: peer, node: peer_node}
  end

  defp stop_peer(%{peer: peer}) do
    :peer.stop(peer)
  catch
    :exit, _reason -> :ok
  end

  defp cleanup_remote_session(peer_node, session_id) do
    case :rpc.call(peer_node, Registry, :lookup, [Beamwarden.SessionRegistry, session_id]) do
      [{_pid, _value}] -> :rpc.call(peer_node, Beamwarden.SessionServer, :stop, [session_id])
      [] -> :ok
      {:badrpc, _reason} -> :ok
    end

    File.rm(Path.join(Beamwarden.session_root(), "#{session_id}.json"))
  end

  defp cleanup_remote_workflow(peer_node, workflow_id) do
    case :rpc.call(peer_node, Registry, :lookup, [Beamwarden.WorkflowRegistry, workflow_id]) do
      [{_pid, _value}] -> :rpc.call(peer_node, Beamwarden.WorkflowServer, :stop, [workflow_id])
      [] -> :ok
      {:badrpc, _reason} -> :ok
    end

    File.rm(Beamwarden.workflow_path(workflow_id))
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
