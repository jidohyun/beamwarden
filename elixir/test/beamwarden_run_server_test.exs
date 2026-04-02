defmodule BeamwardenRunServerTest do
  use ExUnit.Case, async: false

  test "run can exist with zero workers and stays pending" do
    run_id = unique_id("pending-run")

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo", run_id: run_id, workers: 0)

    assert snapshot.run_id == run_id
    assert snapshot.status == "pending"
    assert snapshot.task_count == 1
    assert snapshot.pending_count == 1
    assert snapshot.worker_ids == []

    assert {:ok, persisted} = Beamwarden.RunStore.load(run_id)
    assert persisted["status"] == "pending"
  end

  test "run completes with a supervised local external worker" do
    run_id = unique_id("completed-run")

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 1_500
             )

    assert snapshot.run_id == run_id
    assert snapshot.status == "completed"
    assert snapshot.completed_count == 1
    assert snapshot.failed_count == 0
    assert length(snapshot.tasks) == 1

    [task] = snapshot.tasks
    assert task.status == "completed"
    assert task.result_summary == "review this repo"

    workers = Beamwarden.Orchestrator.worker_list(run_id: run_id)
    assert Enum.any?(workers, &(worker_value(&1, :state) == "idle"))
    assert Enum.any?(workers, &(worker_value(&1, :last_task_status) == "completed"))
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp worker_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
