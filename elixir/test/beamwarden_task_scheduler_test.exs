defmodule BeamwardenTaskSchedulerTest do
  use ExUnit.Case, async: true

  test "build_tasks creates at least one task and annotates multi-worker titles" do
    single = Beamwarden.TaskScheduler.build_tasks("review repo", 1)
    multi = Beamwarden.TaskScheduler.build_tasks("review repo", 2)

    assert length(single) == 1
    assert hd(single).title == "review repo"

    assert Enum.map(multi, & &1.id) == ["1", "2"]
    assert Enum.all?(multi, &String.contains?(&1.title, "review repo"))
    assert Enum.at(multi, 0).title =~ "[1/2]"
    assert Enum.at(multi, 1).title =~ "[2/2]"
  end

  test "assignment and completion update task counts" do
    tasks =
      "demo"
      |> Beamwarden.TaskScheduler.build_tasks(2)
      |> Beamwarden.TaskScheduler.assign_task("1", "worker-1")
      |> Beamwarden.TaskScheduler.complete_task("1", "done")
      |> Beamwarden.TaskScheduler.fail_task("2", "boom")

    assert Beamwarden.TaskScheduler.next_pending_task(tasks) == nil

    assert Beamwarden.TaskScheduler.counts(tasks) == %{
             pending: 0,
             running: 0,
             completed: 1,
             failed: 1
           }
  end
end
