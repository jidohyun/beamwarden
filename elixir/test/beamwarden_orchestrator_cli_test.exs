defmodule BeamwardenOrchestratorCliTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "run, run-status, task-list, and worker-list expose the local orchestration surface" do
    run_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["run", "review this repo", "--workers", "2"])
      end)

    assert run_output =~ "Run Snapshot"
    assert run_output =~ "status=completed"

    run_id =
      run_output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case String.split(line, "=", parts: 2) do
          ["run_id", value] -> value
          _ -> nil
        end
      end)

    assert is_binary(run_id)

    status_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["run-status", run_id])
      end)

    task_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["task-list", run_id])
      end)

    worker_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["worker-list"])
      end)

    assert status_output =~ "run_id=#{run_id}"
    assert task_output =~ "[completed]"
    assert task_output =~ "attempt=1"
    assert task_output =~ "summary=review this repo"
    assert worker_output =~ "active_count="
    assert worker_output =~ "presence=active"
    assert worker_output =~ "run_id=#{run_id}"
  end

  test "cancel-run, retry-task, logs, and persisted worker reporting expose phase 2 lifecycle data" do
    run_id = unique_id("phase-2-run")
    parent = self()

    executor = fn task ->
      send(parent, {:worker_attempt_started, task.task_id, task.attempt})

      receive do
        {:release_attempt, attempt} when attempt == task.attempt ->
          {:ok, "attempt #{task.attempt} complete"}
      after
        1_500 ->
          {:error, "timed out waiting for release"}
      end
    end

    assert {:ok, initial_snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = initial_snapshot.tasks
    [worker_id] = initial_snapshot.worker_ids

    assert_receive {:worker_attempt_started, ^task.task_id, 1}, 1_000

    cancel_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["cancel-run", run_id])
      end)

    assert cancel_output =~ "status=cancelled"
    assert cancel_output =~ "cancelled_count=1"

    assert {:ok, worker_pid} = Beamwarden.WorkerSupervisor.worker_pid(worker_id)
    send(worker_pid, {:release_attempt, 1})

    wait_until(fn ->
      case Beamwarden.Orchestrator.run_snapshot(run_id) do
        {:ok, snapshot} -> Enum.any?(snapshot.tasks, &(&1.status == "cancelled"))
        _ -> false
      end
    end)

    retry_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["retry-task", run_id, task.task_id])
      end)

    assert retry_output =~ "status=running"
    assert retry_output =~ "cancelled_count=0"

    assert_receive {:worker_attempt_started, ^task.task_id, 2}, 1_000
    send(worker_pid, {:release_attempt, 2})

    wait_until(fn ->
      match?({:ok, %{status: "completed"}}, Beamwarden.Orchestrator.run_snapshot(run_id))
    end)

    logs_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["logs", run_id])
      end)

    assert logs_output =~ "run_cancelled"
    assert logs_output =~ "task_retried"
    assert logs_output =~ "worker_result_ignored"
    assert logs_output =~ "task_completed"

    GenServer.stop(worker_pid, :normal)

    worker_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["worker-list"])
      end)

    assert worker_output =~ "persisted_only_count="
    assert worker_output =~ "presence=persisted"
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp wait_until(fun, attempts \\ 80)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")
end
