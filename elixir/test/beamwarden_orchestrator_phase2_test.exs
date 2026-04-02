defmodule BeamwardenOrchestratorPhase2Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "worker-list distinguishes active worker state from persisted worker state" do
    run_id = unique_id("phase2-workers")
    worker_id = "#{run_id}-worker-1"

    Beamwarden.WorkerStore.save(%{
      worker_id: worker_id,
      run_id: run_id,
      state: "failed",
      current_task_id: "persisted-task",
      started_at: "persisted-started-at",
      heartbeat_at: "persisted-heartbeat-at",
      last_event_at: "persisted-last-event-at",
      last_result_summary: "persisted boom"
    })

    assert {:ok, ^worker_id} =
             Beamwarden.WorkerSupervisor.start_worker(run_id,
               worker_id: worker_id,
               executor: fn _task -> {:ok, "done"} end
             )

    on_exit(fn ->
      case Registry.lookup(Beamwarden.ExternalWorkerRegistry, worker_id) do
        [{pid, _value}] -> Process.exit(pid, :kill)
        [] -> :ok
      end
    end)

    assert wait_until(fn ->
             Enum.any?(
               Beamwarden.WorkerSupervisor.list_live_workers(run_id: run_id),
               &(worker_value(&1, :worker_id) == worker_id)
             )
           end)

    worker_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["worker-list"])
      end)

    assert worker_output =~ "worker_id=#{worker_id}"
    assert worker_output =~ "active_state="
    assert worker_output =~ "persisted_state="
    assert worker_output =~ "active_current_task_id="
    assert worker_output =~ "persisted_current_task_id=persisted-task"
  end

  test "retry-task requeues a failed task and clears the prior failure" do
    run_id = unique_id("phase2-retry")
    {:ok, mode} = Agent.start_link(fn -> :fail_once end)

    on_exit(fn ->
      if Process.alive?(mode), do: Agent.stop(mode)
    end)

    executor = fn _task ->
      Agent.get_and_update(mode, fn
        :fail_once -> {{:error, "boom"}, :succeed}
        :succeed -> {{:ok, "retried"}, :succeed}
      end)
    end

    assert {:ok, failed_snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 1_500,
               worker_opts: [executor: executor]
             )

    assert failed_snapshot.status == "failed"
    [failed_task] = failed_snapshot.tasks
    assert failed_task.error == "boom"

    retry_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["retry-task", run_id, failed_task.task_id])
      end)

    assert retry_output =~ "run_id=#{run_id}"

    assert wait_until(fn ->
             match?({:ok, %{status: "completed"}}, Beamwarden.Orchestrator.run_snapshot(run_id))
           end)

    assert {:ok, retried_snapshot} = Beamwarden.Orchestrator.run_snapshot(run_id)
    assert retried_snapshot.status == "completed"
    assert retried_snapshot.failed_count == 0
    assert retried_snapshot.completed_count == 1
    assert hd(retried_snapshot.tasks).result_summary == "retried"
    assert hd(retried_snapshot.tasks).error == nil
  end

  test "cancel-run transitions a queued run into cancelled state" do
    run_id = unique_id("phase2-cancel")

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo", run_id: run_id, workers: 0)

    assert snapshot.status == "pending"

    cancel_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cancel-run", run_id])
      end)

    assert cancel_output =~ "run_id=#{run_id}"
    assert cancel_output =~ "status=cancelled"

    assert {:ok, cancelled_snapshot} = Beamwarden.Orchestrator.run_snapshot(run_id)
    assert cancelled_snapshot.status == "cancelled"
    assert Enum.all?(cancelled_snapshot.tasks, &(&1.status == "cancelled"))
  end

  test "logs renders persisted task and worker summaries for a finished run" do
    run_id = unique_id("phase2-logs")

    assert {:ok, failed_snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 1_500,
               worker_opts: [command: "printf 'boom' >&2; exit 2"]
             )

    assert failed_snapshot.status == "failed"
    [failed_task] = failed_snapshot.tasks

    logs_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["logs", run_id])
      end)

    assert logs_output =~ "Run Logs"
    assert logs_output =~ "run_id=#{run_id}"
    assert logs_output =~ failed_task.task_id
    assert logs_output =~ "failed"
    assert logs_output =~ "boom"
  end

  defp wait_until(fun, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(25)
        do_wait_until(fun, deadline)
      end
    end
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp worker_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
