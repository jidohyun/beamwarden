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
    assert task_output =~ "summary=review this repo"
    assert worker_output =~ "run_id=#{run_id}"
  end
end
