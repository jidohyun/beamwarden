defmodule BeamwardenTaskSchedulerTest do
  use ExUnit.Case, async: true

  test "initial_tasks splits prompt and tracks task transitions" do
    tasks = Beamwarden.TaskScheduler.initial_tasks("run-123", "review repo || propose fixes")

    assert Enum.map(tasks, & &1.task_id) == ["1", "2"]
    assert Enum.map(tasks, & &1.status) == ["pending", "pending"]

    {task, tasks} = Beamwarden.TaskScheduler.assign_next_task(tasks, "worker-1")
    assert task.task_id == "1"
    assert task.status == "running"
    assert task.assigned_worker == "worker-1"

    tasks = Beamwarden.TaskScheduler.finish_task(tasks, "1", "worker-1", {:ok, "done"})
    counts = Beamwarden.TaskScheduler.counts(tasks)

    assert counts.completed_count == 1
    assert counts.pending_count == 1
    refute Beamwarden.TaskScheduler.terminal?(tasks)
    assert Beamwarden.TaskScheduler.run_status(tasks) == "running"

    tasks = Beamwarden.TaskScheduler.finish_task(tasks, "2", "worker-2", {:error, "boom"})

    assert Beamwarden.TaskScheduler.terminal?(tasks)
    assert Beamwarden.TaskScheduler.run_status(tasks) == "failed"
    assert Enum.find(tasks, &(&1.task_id == "2")).error == "boom"
  end
end
