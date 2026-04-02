defmodule BeamwardenTaskSchedulerTest do
  use ExUnit.Case, async: false

  alias Beamwarden.TaskScheduler

  test "assign_next_task uses FIFO ordering and never assigns the same task twice" do
    tasks = [
      %{
        task_id: "task-1",
        run_id: "run-1",
        title: "first",
        payload: "first",
        status: "pending",
        assigned_worker: nil,
        result_summary: nil,
        error: nil,
        created_at: "now",
        updated_at: "now"
      },
      %{
        task_id: "task-2",
        run_id: "run-1",
        title: "second",
        payload: "second",
        status: "pending",
        assigned_worker: nil,
        result_summary: nil,
        error: nil,
        created_at: "now",
        updated_at: "now"
      }
    ]

    assert {:ok, first_task, tasks} = TaskScheduler.assign_next_task(tasks, "worker-1")
    assert first_task.task_id == "task-1"
    assert Enum.at(tasks, 0).status == "in_progress"
    assert Enum.at(tasks, 0).assigned_worker == "worker-1"

    assert {:ok, second_task, tasks} = TaskScheduler.assign_next_task(tasks, "worker-2")
    assert second_task.task_id == "task-2"
    assert Enum.at(tasks, 1).status == "in_progress"
    assert Enum.at(tasks, 1).assigned_worker == "worker-2"

    assert :none = TaskScheduler.assign_next_task(tasks, "worker-3")
  end

  test "completion/failure counts drive the aggregate run status" do
    tasks = TaskScheduler.build_initial_tasks("run-2", "review this repo")
    assert TaskScheduler.status(tasks, 0) == "pending"

    assert {:ok, task, tasks} = TaskScheduler.assign_next_task(tasks, "worker-1")
    assert TaskScheduler.status(tasks, 1) == "running"

    tasks = TaskScheduler.complete_task(tasks, task.task_id, "worker-1", "done")
    counts = TaskScheduler.counts(tasks)

    assert counts.completed_count == 1
    assert counts.failed_count == 0
    assert TaskScheduler.status(tasks, 1) == "completed"

    failed = TaskScheduler.build_initial_tasks("run-3", "review this repo")
    assert {:ok, failed_task, failed} = TaskScheduler.assign_next_task(failed, "worker-2")
    failed = TaskScheduler.fail_task(failed, failed_task.task_id, "worker-2", "boom")

    assert TaskScheduler.counts(failed).failed_count == 1
    assert TaskScheduler.status(failed, 1) == "failed"
  end
end
