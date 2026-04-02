defmodule BeamwardenOrchestratorPhase4ReviewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "run snapshot marks persisted non-terminal runs as stale runtime evidence" do
    run_id = unique_id("phase4-stale")
    on_exit(fn -> cleanup_run_artifacts(run_id) end)

    Beamwarden.RunStore.save(%{
      run_id: run_id,
      prompt: "recover this run",
      status: "running",
      lifecycle: "active",
      created_at: "2000-01-01T00:00:00Z",
      updated_at: "2000-01-01T00:00:00Z",
      task_ids: ["#{run_id}-task-1"],
      worker_ids: ["#{run_id}-worker-1"],
      tasks: [
        %{
          task_id: "#{run_id}-task-1",
          run_id: run_id,
          title: "recover run",
          payload: "recover run",
          attempt: 1,
          status: "in_progress",
          assigned_worker: "#{run_id}-worker-1",
          created_at: "2000-01-01T00:00:00Z",
          updated_at: "2000-01-01T00:00:00Z"
        }
      ],
      task_count: 1,
      pending_count: 0,
      running_count: 1,
      cancelling_count: 0,
      completed_count: 0,
      failed_count: 0,
      cancelled_count: 0
    })

    assert {:ok, snapshot} = Beamwarden.Orchestrator.run_snapshot(run_id)
    assert snapshot["presence"] == "persisted"
    assert snapshot["stale_runtime"] == true
    assert snapshot["stale_reason"] == "run_server_not_registered"

    output = Beamwarden.Orchestrator.render_run(snapshot)
    assert output =~ "presence=persisted"
    assert output =~ "status=running"
    assert output =~ "lifecycle=active"
    assert output =~ "stale_runtime=true"
    assert output =~ "stale_reason=run_server_not_registered"
  end

  test "worker-list distinguishes active workers from persisted-only history" do
    run_id = unique_id("phase4-workers")
    persisted_worker_id = "#{run_id}-worker-persisted"
    parent = self()

    on_exit(fn ->
      send(parent, :release_phase4_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running("#{run_id}-worker-1")
      cleanup_run_artifacts(run_id)
      File.rm(Beamwarden.worker_path(persisted_worker_id))
    end)

    Beamwarden.WorkerStore.save(%{
      worker_id: persisted_worker_id,
      run_id: run_id,
      state: "failed",
      current_task_id: "#{run_id}-task-persisted",
      started_at: "2000-01-01T00:00:00Z",
      heartbeat_at: "2000-01-01T00:00:00Z",
      last_event_at: "2000-01-01T00:00:00Z",
      last_task_status: "failed"
    })

    executor = fn task ->
      send(parent, {:phase4_worker_started, task.task_id, task.attempt})

      receive do
        :release_phase4_worker -> {:ok, "worker released"}
      after
        1_500 -> {:error, "timed out waiting for phase4 worker release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4_worker_started, ^task_id, 1}, 1_000

    workers = Beamwarden.Orchestrator.worker_list(run_id: run_id)
    output = Beamwarden.Orchestrator.render_workers(workers)

    assert output =~ "active_count=1"
    assert output =~ "persisted_only_count=1"
    assert output =~ "worker_id=#{run_id}-worker-1"
    assert output =~ "presence=active"
    assert output =~ "worker_id=#{persisted_worker_id}"
    assert output =~ "presence=persisted"
  end

  test "cleanup-state skips active runs, workers, and event files even at zero-second retention" do
    run_id = unique_id("phase4-cleanup-active")
    worker_id = "#{run_id}-worker-1"
    parent = self()

    on_exit(fn ->
      send(parent, :release_cleanup_worker)
      stop_run_if_running(run_id)
      stop_worker_if_running(worker_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:cleanup_worker_started, task.task_id, task.attempt})

      receive do
        :release_cleanup_worker -> {:ok, "cleanup released"}
      after
        1_500 -> {:error, "timed out waiting for cleanup release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("keep this run active",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:cleanup_worker_started, ^task_id, 1}, 1_000

    assert File.exists?(Beamwarden.run_path(run_id))
    assert File.exists?(Beamwarden.worker_path(worker_id))
    assert File.exists?(Beamwarden.event_path(run_id))

    cleanup_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "cleanup-state",
                   "--older-than-seconds",
                   "0"
                 ])
      end)

    assert cleanup_output =~ "deleted_run_count=0"
    assert cleanup_output =~ "deleted_worker_count=0"
    assert cleanup_output =~ "deleted_event_count=0"
    assert File.exists?(Beamwarden.run_path(run_id))
    assert File.exists?(Beamwarden.worker_path(worker_id))
    assert File.exists?(Beamwarden.event_path(run_id))
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
