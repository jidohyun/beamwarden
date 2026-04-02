defmodule BeamwardenOrchestratorPhase3Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "run-status includes lifecycle metadata for active orchestration runs" do
    run_id = unique_id("phase3-lifecycle")
    on_exit(fn -> cleanup_run_artifacts(run_id) end)

    assert {:ok, _snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 1_500
             )

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["run-status", run_id])
      end)

    assert output =~ "run_id=#{run_id}"
    assert output =~ "lifecycle=active"
  end

  test "logs surfaces persisted lifecycle/source semantics when follow is requested" do
    run_id = unique_id("phase3-logs")
    task_id = "#{run_id}-task-1"
    timestamp = stale_timestamp()

    on_exit(fn -> cleanup_run_artifacts(run_id) end)

    Beamwarden.RunStore.save(
      run_snapshot(run_id, task_id,
        status: "failed",
        lifecycle: "active",
        updated_at: timestamp,
        failed_count: 1
      )
    )

    Beamwarden.EventStore.append(run_id, %{
      type: "task_failed",
      task_id: task_id,
      error: "boom",
      timestamp: timestamp
    })

    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["logs", run_id, "--follow"])
      end)

    assert output =~ "run_status=failed"
    assert output =~ "run_lifecycle=active"
    assert output =~ "event_source=persisted"
    assert output =~ "follow_supported=false"
    assert output =~ "follow=requested_persisted_snapshot_replayed_once"
    assert output =~ "task_failed"
    assert output =~ "error=boom"
  end

  test "cleanup-runs prunes expired persisted runs, workers, and events while keeping active runs" do
    expired_run_id = unique_id("phase3-expired")
    expired_task_id = "#{expired_run_id}-task-1"
    active_run_id = unique_id("phase3-active")
    orphan_worker_id = "#{expired_run_id}-orphan-worker"
    stale = stale_timestamp()

    on_exit(fn ->
      cleanup_run_artifacts(expired_run_id)
      cleanup_run_artifacts(active_run_id)
      File.rm(Beamwarden.worker_path(orphan_worker_id))
    end)

    Beamwarden.RunStore.save(
      run_snapshot(expired_run_id, expired_task_id,
        status: "completed",
        lifecycle: "active",
        updated_at: stale,
        completed_count: 1
      )
    )

    Beamwarden.WorkerStore.save(%{
      worker_id: "#{expired_run_id}-worker-1",
      run_id: expired_run_id,
      state: "idle",
      current_task_id: nil,
      last_task_status: "completed",
      started_at: stale,
      heartbeat_at: stale,
      last_event_at: stale,
      last_result_summary: "done"
    })

    Beamwarden.WorkerStore.save(%{
      worker_id: orphan_worker_id,
      run_id: nil,
      state: "idle",
      current_task_id: nil,
      last_task_status: "failed",
      started_at: stale,
      heartbeat_at: stale,
      last_event_at: stale,
      last_result_summary: "orphaned"
    })

    Beamwarden.EventStore.append(expired_run_id, %{
      type: "run_completed",
      completed_count: 1,
      timestamp: stale
    })

    assert {:ok, _snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: active_run_id,
               workers: 1,
               await_timeout: 1_500
             )

    cleanup_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cleanup-runs", "--ttl-seconds", "0"])
      end)

    assert cleanup_output =~ "deleted_run_count=1"
    assert cleanup_output =~ "deleted_worker_count=2"
    assert cleanup_output =~ "deleted_event_count=1"
    assert cleanup_output =~ "deleted_runs=#{expired_run_id}"
    assert cleanup_output =~ "skipped_active_runs="
    assert cleanup_output =~ active_run_id

    refute File.exists?(Beamwarden.run_path(expired_run_id))
    refute File.exists?(Beamwarden.worker_path("#{expired_run_id}-worker-1"))
    refute File.exists?(Beamwarden.worker_path(orphan_worker_id))
    refute File.exists?(Beamwarden.event_path(expired_run_id))

    assert File.exists?(Beamwarden.run_path(active_run_id))
  end

  defp run_snapshot(run_id, task_id, opts) do
    status = Keyword.fetch!(opts, :status)
    lifecycle = Keyword.get(opts, :lifecycle, "active")
    updated_at = Keyword.fetch!(opts, :updated_at)
    completed_count = Keyword.get(opts, :completed_count, 0)
    failed_count = Keyword.get(opts, :failed_count, 0)
    cancelled_count = Keyword.get(opts, :cancelled_count, 0)

    %{
      run_id: run_id,
      prompt: "review this repo",
      status: status,
      lifecycle: lifecycle,
      created_at: updated_at,
      updated_at: updated_at,
      task_ids: [task_id],
      worker_ids: [],
      tasks: [
        %{
          task_id: task_id,
          run_id: run_id,
          title: "review this repo",
          payload: "review this repo",
          attempt: 1,
          status: status,
          assigned_worker: nil,
          result_summary: if(status == "completed", do: "done"),
          error: if(status == "failed", do: "boom"),
          created_at: updated_at,
          updated_at: updated_at
        }
      ],
      task_count: 1,
      pending_count: 0,
      running_count: 0,
      completed_count: completed_count,
      failed_count: failed_count,
      cancelled_count: cancelled_count
    }
  end

  defp cleanup_run_artifacts(run_id) do
    if Registry.lookup(Beamwarden.RunRegistry, run_id) != [] do
      [{pid, _value}] = Registry.lookup(Beamwarden.RunRegistry, run_id)
      GenServer.stop(pid, :normal)
    end

    Beamwarden.RunStore.delete(run_id)
    Beamwarden.EventStore.delete(run_id)

    Beamwarden.WorkerStore.list(run_id: run_id)
    |> Enum.each(fn worker ->
      if Registry.lookup(
           Beamwarden.ExternalWorkerRegistry,
           worker["worker_id"] || worker[:worker_id]
         ) != [] do
        [{pid, _value}] =
          Registry.lookup(
            Beamwarden.ExternalWorkerRegistry,
            worker["worker_id"] || worker[:worker_id]
          )

        Process.exit(pid, :kill)
      end

      Beamwarden.WorkerStore.delete(worker["worker_id"] || worker[:worker_id])
    end)
  end

  defp stale_timestamp do
    DateTime.utc_now()
    |> DateTime.add(-3_600, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
