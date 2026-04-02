defmodule BeamwardenOrchestratorPhase3Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "logs --follow streams persisted events until the run reaches a terminal state" do
    run_id = unique_id("phase3-follow")
    parent = self()

    executor = fn task ->
      send(parent, {:follow_worker_started, task.task_id, task.attempt})

      receive do
        :release_follow_worker -> {:ok, "follow complete"}
      after
        1_500 -> {:error, "timed out waiting for follow release"}
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
    assert_receive {:follow_worker_started, ^task.task_id, 1}, 1_000

    follower =
      Task.async(fn ->
        capture_io(fn ->
          assert 0 ==
                   Beamwarden.CLI.main([
                     "logs",
                     run_id,
                     "--follow",
                     "--follow-interval-ms",
                     "25",
                     "--follow-timeout-ms",
                     "1500"
                   ])
        end)
      end)

    Process.sleep(100)
    send(parent, :release_follow_worker)

    output = Task.await(follower, 2_000)

    assert output =~ "Run Logs"
    assert output =~ "follow=streaming"
    assert output =~ "task_assigned"
    assert output =~ "task_completed"
    assert output =~ "follow=complete status=completed"
  end

  test "cleanup-state removes expired persisted runs, workers, and events" do
    run_id = unique_id("phase3-cleanup")
    worker_id = "#{run_id}-worker-1"
    old_time = "2000-01-01T00:00:00Z"

    Beamwarden.RunStore.save(%{
      run_id: run_id,
      prompt: "cleanup me",
      status: "completed",
      lifecycle: "active",
      created_at: old_time,
      updated_at: old_time,
      finished_at: old_time,
      task_ids: ["#{run_id}-task-1"],
      worker_ids: [worker_id],
      tasks: [],
      task_count: 1,
      pending_count: 0,
      running_count: 0,
      cancelling_count: 0,
      completed_count: 1,
      failed_count: 0,
      cancelled_count: 0
    })

    Beamwarden.WorkerStore.save(%{
      worker_id: worker_id,
      run_id: run_id,
      state: "idle",
      started_at: old_time,
      heartbeat_at: old_time,
      last_event_at: old_time
    })

    File.mkdir_p!(Beamwarden.event_root())

    Beamwarden.event_path(run_id)
    |> File.write!(~s({"run_id":"#{run_id}","type":"run_completed","timestamp":"#{old_time}"}\n))

    cleanup_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "cleanup-state",
                   "--older-than-seconds",
                   "60"
                 ])
      end)

    assert cleanup_output =~ "runs_deleted=1"
    assert cleanup_output =~ "workers_deleted=1"
    assert cleanup_output =~ "events_deleted=1"
    refute File.exists?(Beamwarden.run_path(run_id))
    refute File.exists?(Beamwarden.worker_path(worker_id))
    refute File.exists?(Beamwarden.event_path(run_id))
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
