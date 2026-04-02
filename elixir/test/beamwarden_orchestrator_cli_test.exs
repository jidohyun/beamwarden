defmodule BeamwardenOrchestratorCLITest do
  use ExUnit.Case, async: false

  setup do
    cleanup_runs()
    original_command = Beamwarden.AppIdentity.get_env(:orchestrator_worker_command)

    Beamwarden.AppIdentity.put_env(
      :orchestrator_worker_command,
      {"/bin/sh", ["-lc", "printf 'cli:%s\\n' \"$BW_TASK_PAYLOAD\""]}
    )

    on_exit(fn ->
      cleanup_runs()
      restore_env(:orchestrator_worker_command, original_command)
    end)

    :ok
  end

  test "cli run, run-status, task-list, and worker-list report orchestration state" do
    assert {:ok, output} =
             Beamwarden.CLI.run(["run", "review repo || propose fixes", "--workers", "2"])

    assert output =~ "Run Summary"

    run_id = capture_value(output, "run_id")

    status_output =
      wait_until(
        fn -> Beamwarden.CLI.run(["run-status", run_id]) end,
        fn
          {:ok, text} -> String.contains?(text, "status=completed")
          _ -> false
        end
      )

    assert {:ok, status_text} = status_output
    assert status_text =~ "completed_count=2"

    assert {:ok, task_output} = Beamwarden.CLI.run(["task-list", run_id])
    assert task_output =~ "Task List"
    assert task_output =~ "[completed] 1"
    assert task_output =~ "[completed] 2"

    assert {:ok, worker_output} = Beamwarden.CLI.run(["worker-list"])
    assert worker_output =~ "Worker List"
    assert worker_output =~ "run_id=#{run_id}"
    assert worker_output =~ "state=idle"
  end

  defp cleanup_runs do
    Beamwarden.RunServer.list_runs()
    |> Enum.each(fn run -> Beamwarden.RunServer.stop(run.run_id) end)
  end

  defp capture_value(output, key) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, "=", parts: 2) do
        [^key, value] -> value
        _ -> nil
      end
    end)
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
