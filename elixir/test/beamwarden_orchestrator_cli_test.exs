defmodule BeamwardenOrchestratorCliTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    on_exit(fn ->
      Beamwarden.RunServer.list_run_ids()
      |> Enum.each(fn run_id ->
        _ = Beamwarden.RunServer.stop(run_id)
      end)
    end)

    :ok
  end

  test "run command starts a local orchestration run and exposes status/tasks/workers" do
    run_id = "run-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    run_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main(["run", "review repo", "--workers", "2", "--run-id", run_id])
      end)

    assert run_output =~ "# Orchestration Run"
    assert run_output =~ "run_id=#{run_id}"

    snapshot = wait_for_run(run_id)
    assert snapshot.status == "completed"
    assert snapshot.task_counts.completed == 2

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

    assert status_output =~ "status=completed"
    assert task_output =~ "[completed] 1"
    assert task_output =~ "[completed] 2"
    assert worker_output =~ "run_id=#{run_id}"
    assert worker_output =~ "state=idle"
  end

  test "run-status reports not found for unknown ids" do
    output =
      capture_io(fn ->
        assert 1 == Beamwarden.CLI.main(["run-status", "missing-run"])
      end)

    assert output =~ "Run not found"
  end

  defp wait_for_run(run_id, attempts \\ 20)

  defp wait_for_run(run_id, 0), do: Beamwarden.RunServer.snapshot(run_id)

  defp wait_for_run(run_id, attempts) do
    snapshot = Beamwarden.RunServer.snapshot(run_id)

    if snapshot.status in ["completed", "failed"] do
      snapshot
    else
      Process.sleep(25)
      wait_for_run(run_id, attempts - 1)
    end
  end
end
