defmodule BeamwardenRunServerTest do
  use ExUnit.Case, async: false

  setup do
    cleanup_runs()
    original_command = Beamwarden.AppIdentity.get_env(:orchestrator_worker_command)

    Beamwarden.AppIdentity.put_env(
      :orchestrator_worker_command,
      {"/bin/sh", ["-lc", "printf 'done:%s\\n' \"$BW_TASK_PAYLOAD\""]}
    )

    on_exit(fn ->
      cleanup_runs()
      restore_env(:orchestrator_worker_command, original_command)
    end)

    :ok
  end

  test "run server dispatches tasks across workers and completes the run" do
    {:ok, snapshot} = Beamwarden.RunServer.start_run("review repo || propose fixes", workers: 2)
    run_id = snapshot.run_id

    completed =
      wait_until(fn -> Beamwarden.RunServer.snapshot(run_id) end, &(&1.status == "completed"))

    assert completed.completed_count == 2
    assert completed.failed_count == 0
    assert completed.worker_count == 2

    tasks = Beamwarden.RunServer.list_tasks(run_id)

    assert Enum.map(tasks, & &1.status) == ["completed", "completed"]
    assert Enum.all?(tasks, &String.starts_with?(&1.result_summary, "done:"))

    workers = Beamwarden.ExternalWorker.list_workers() |> Enum.filter(&(&1.run_id == run_id))
    assert length(workers) == 2
    assert Enum.all?(workers, &(&1.state == "idle"))
  end

  defp cleanup_runs do
    Beamwarden.RunServer.list_runs()
    |> Enum.each(fn run -> Beamwarden.RunServer.stop(run.run_id) end)
  end

  defp restore_env(key, nil), do: Beamwarden.AppIdentity.delete_env(key)
  defp restore_env(key, value), do: Beamwarden.AppIdentity.put_env(key, value)

  defp wait_until(fetcher, predicate, attempts \\ 50)

  defp wait_until(fetcher, predicate, 0) do
    value = fetcher.()
    assert predicate.(value), "condition not met for #{inspect(value)}"
    value
  end

  defp wait_until(fetcher, predicate, attempts) do
    value = fetcher.()

    if predicate.(value) do
      value
    else
      Process.sleep(20)
      wait_until(fetcher, predicate, attempts - 1)
    end
  end
end
