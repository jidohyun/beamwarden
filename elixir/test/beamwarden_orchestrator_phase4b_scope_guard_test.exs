defmodule BeamwardenOrchestratorPhase4bScopeGuardTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "worker liveness slice leaves run-status and task-list focused on run/task data" do
    run_id = unique_id("phase4b-scope-status")
    parent = self()

    on_exit(fn ->
      send(parent, :release_scope_guard_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running("#{run_id}-worker-1")
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:scope_guard_worker_started, task.task_id, task.attempt})

      receive do
        :release_scope_guard_worker -> {:ok, "scope guard released"}
      after
        1_500 -> {:error, "timed out waiting for scope guard release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("scope guard review",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:scope_guard_worker_started, ^task_id, 1}, 1_000

    status_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["run-status", run_id])
      end)

    task_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    assert status_output =~ "Run Snapshot"
    assert status_output =~ "run_id=#{run_id}"
    assert status_output =~ "status=running"
    refute status_output =~ "worker_health="
    refute status_output =~ "last_heartbeat_at="
    refute status_output =~ "stale_after_seconds="

    assert task_output =~ "Run Tasks"
    assert task_output =~ "worker=#{run_id}-worker-1"
    assert task_output =~ "attempt=1"
    refute task_output =~ "worker_health="
    refute task_output =~ "last_heartbeat_at="
    refute task_output =~ "stale_after_seconds="
  end

  test "worker liveness slice does not turn cleanup or follow output into lease/tail/tui surfaces" do
    cleanup_run_id = unique_id("phase4b-scope-cleanup")
    follow_run_id = unique_id("phase4b-scope-follow")
    parent = self()

    on_exit(fn ->
      send(parent, :release_scope_cleanup_worker)
      send(parent, :release_scope_follow_worker)
      stop_run_if_running(cleanup_run_id)
      stop_run_if_running(follow_run_id)
      stop_worker_if_running("#{cleanup_run_id}-worker-1")
      stop_worker_if_running("#{follow_run_id}-worker-1")
      cleanup_run_artifacts(cleanup_run_id)
      cleanup_run_artifacts(follow_run_id)
    end)

    cleanup_executor = fn task ->
      send(parent, {:scope_cleanup_worker_started, task.task_id, task.attempt})

      receive do
        :release_scope_cleanup_worker -> {:ok, "cleanup scope released"}
      after
        1_500 -> {:error, "timed out waiting for cleanup scope release"}
      end
    end

    assert {:ok, cleanup_snapshot} =
             Beamwarden.Orchestrator.start_run("cleanup scope guard",
               run_id: cleanup_run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: cleanup_executor]
             )

    [cleanup_task] = cleanup_snapshot.tasks
    cleanup_task_id = cleanup_task.task_id
    assert_receive {:scope_cleanup_worker_started, ^cleanup_task_id, 1}, 1_000

    cleanup_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cleanup-state", "--older-than-seconds", "0"])
      end)

    assert cleanup_output =~ "Cleanup Runs"
    assert cleanup_output =~ "skipped_active_count=1"
    refute cleanup_output =~ "skip=active_lease"
    refute cleanup_output =~ "skip=recovery_window"
    refute cleanup_output =~ "skip=reachable_owner"

    follow_executor = fn task ->
      send(parent, {:scope_follow_worker_started, task.task_id, task.attempt})

      receive do
        :release_scope_follow_worker -> {:ok, "follow scope released"}
      after
        1_500 -> {:error, "timed out waiting for follow scope release"}
      end
    end

    assert {:ok, follow_snapshot} =
             Beamwarden.Orchestrator.start_run("follow scope guard",
               run_id: follow_run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: follow_executor]
             )

    [follow_task] = follow_snapshot.tasks
    follow_task_id = follow_task.task_id
    assert_receive {:scope_follow_worker_started, ^follow_task_id, 1}, 1_000

    follower =
      Task.async(fn ->
        capture_io(fn ->
          assert 0 ==
                   Beamwarden.CLI.main([
                     "logs",
                     follow_run_id,
                     "--follow",
                     "--follow-interval-ms",
                     "25",
                     "--follow-timeout-ms",
                     "1500"
                   ])
        end)
      end)

    Process.sleep(100)
    send(parent, :release_scope_follow_worker)

    follow_output = Task.await(follower, 2_000)

    assert follow_output =~ "Run Logs"
    assert follow_output =~ "follow=live"
    assert follow_output =~ "source=replay"
    assert follow_output =~ "source=live"
    refute follow_output =~ "worker_stdout"
    refute follow_output =~ "worker_stderr"
    refute follow_output =~ "monitor"
    refute follow_output =~ "tui"
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
