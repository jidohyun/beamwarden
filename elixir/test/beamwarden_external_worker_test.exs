defmodule BeamwardenExternalWorkerTest do
  use ExUnit.Case, async: false

  test "external worker normalizes successful command output" do
    run_id = unique_id("worker-success")

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("payload",
               run_id: run_id,
               workers: 1,
               worker_opts: [command: "printf 'done:%s' \"$BEAMWARDEN_TASK_PAYLOAD\""],
               await_timeout: 1_500
             )

    assert snapshot.status == "completed"
    assert hd(snapshot.tasks).result_summary == "done:payload"
  end

  test "external worker normalizes failures into failed task state" do
    run_id = unique_id("worker-failure")

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("payload",
               run_id: run_id,
               workers: 1,
               worker_opts: [command: "printf 'boom' >&2; exit 2"],
               await_timeout: 1_500
             )

    assert snapshot.status == "failed"
    assert snapshot.failed_count == 1
    assert hd(snapshot.tasks).error == "boom"
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
