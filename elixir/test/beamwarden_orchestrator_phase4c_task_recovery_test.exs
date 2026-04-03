defmodule BeamwardenOrchestratorPhase4cTaskRecoveryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "healthy in-flight task stays compact while exposing leased assignment state" do
    run_id = unique_id("phase4c-healthy")
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4c_healthy_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running("#{run_id}-worker-1")
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4c_healthy_started, task.task_id, task.attempt})

      receive do
        :release_phase4c_healthy_worker -> {:ok, "healthy released"}
      after
        1_500 -> {:error, "timed out waiting for healthy release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("healthy recovery view",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4c_healthy_started, ^task_id, 1}, 1_000

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert output =~ "assignment_state=leased"
    refute output =~ "recovery_reason="
    refute output =~ "lease_expires_at="
  end

  test "task-list marks stale in-flight work as worker_expired with lease evidence" do
    run_id = unique_id("phase4c-expired")
    worker_id = "#{run_id}-worker-1"
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4c_expired_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running(worker_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4c_expired_started, task.task_id, task.attempt})

      receive do
        :release_phase4c_expired_worker -> {:ok, "expired released"}
      after
        10_000 -> {:error, "timed out waiting for expired release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("stale worker recovery view",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4c_expired_started, ^task_id, 1}, 1_000
    stop_worker_if_running(worker_id)
    File.rm(Beamwarden.worker_path(worker_id))

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert output =~ "worker=#{worker_id}"
    assert output =~ "assignment_state=lost_lease"
    assert output =~ "recovery_reason=worker_expired"
  end

  test "persisted non-terminal task explains daemon_restart instead of implying healthy ownership" do
    run_id = unique_id("phase4c-restart")
    worker_id = "#{run_id}-worker-1"
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4c_restart_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running(worker_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4c_restart_started, task.task_id, task.attempt})

      receive do
        :release_phase4c_restart_worker -> {:ok, "restart released"}
      after
        1_500 -> {:error, "timed out waiting for restart release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("daemon restart recovery view",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4c_restart_started, ^task_id, 1}, 1_000
    stop_run_if_running(run_id)

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert output =~ "assignment_state=lost_lease"
    assert output =~ "recovery_reason=daemon_restart"
    assert output =~ "lease_expires_at="
  end

  test "persisted-only worker ownership is surfaced as node_down recovery evidence" do
    run_id = unique_id("phase4c-node-down")
    worker_id = "#{run_id}-worker-1"
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4c_node_down_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running(worker_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4c_node_down_started, task.task_id, task.attempt})

      receive do
        :release_phase4c_node_down_worker -> {:ok, "node down released"}
      after
        10_000 -> {:error, "timed out waiting for node down release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("node down recovery view",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4c_node_down_started, ^task_id, 1}, 1_000
    stop_worker_if_running(worker_id)

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert output =~ "worker=#{worker_id}"
    assert output =~ "assignment_state=lost_lease"
    assert output =~ "recovery_reason=node_down"
    assert output =~ "lease_expires_at="
  end

  test "operator retry keeps the new assignment explicit without reviving stale failure text" do
    run_id = unique_id("phase4c-retry")
    worker_id = "#{run_id}-worker-1"
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4c_retry_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running(worker_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4c_retry_started, task.task_id, task.attempt})

      case task.attempt do
        1 ->
          {:error, "boom"}

        2 ->
          receive do
            :release_phase4c_retry_worker -> {:ok, "retried"}
          after
            1_500 -> {:error, "timed out waiting for retried release"}
          end
      end
    end

    assert {:ok, failed_snapshot} =
             Beamwarden.Orchestrator.start_run("operator retry recovery view",
               run_id: run_id,
               workers: 1,
               await_timeout: 1_500,
               worker_opts: [executor: executor]
             )

    assert failed_snapshot.status == "failed"
    [failed_task] = failed_snapshot.tasks
    failed_task_id = failed_task.task_id
    assert_receive {:phase4c_retry_started, ^failed_task_id, 1}, 1_000

    retry_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["retry-task", run_id, failed_task_id])
      end)

    assert retry_output =~ "run_id=#{run_id}"
    assert_receive {:phase4c_retry_started, ^failed_task_id, 2}, 1_000

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert output =~ "assignment_state=leased"
    assert output =~ "recovery_reason=operator_retry"
    assert output =~ "recovered_from_attempt=1"
    assert output =~ "recovered_from_worker=#{worker_id}"
    refute output =~ "error=boom"
  end

  test "operator cancellation stays task-list-only and does not leak recovery fields into run-status" do
    run_id = unique_id("phase4c-cancel")

    on_exit(fn ->
      stop_run_if_running(run_id)
      cleanup_run_artifacts(run_id)
    end)

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("cancel recovery view",
               run_id: run_id,
               workers: 0
             )

    [task] = snapshot.tasks
    assert task.status == "pending"

    cancel_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cancel-run", run_id])
      end)

    assert cancel_output =~ "status=cancelled"

    task_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    status_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["run-status", run_id])
      end)

    assert task_output =~ "assignment_state=terminal"
    assert task_output =~ "recovery_reason=cancel_requested"
    refute status_output =~ "assignment_state="
    refute status_output =~ "recovery_reason="
  end

  defp stop_run_if_running(run_id) do
    case Registry.lookup(Beamwarden.RunRegistry, run_id) do
      [{pid, _value} | _] -> GenServer.stop(pid, :normal, 1_000)
      [] -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  defp stop_worker_if_running(worker_id) do
    case Beamwarden.WorkerSupervisor.worker_pid(worker_id) do
      {:ok, pid} -> GenServer.stop(pid, :normal, 1_000)
      :error -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  defp cleanup_run_artifacts(run_id) do
    File.rm(Beamwarden.run_path(run_id))
    File.rm(Beamwarden.event_path(run_id))

    Beamwarden.WorkerStore.list(run_id: run_id)
    |> Enum.each(fn snapshot ->
      File.rm(Beamwarden.worker_path(snapshot["worker_id"] || snapshot[:worker_id]))
    end)
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
