defmodule Beamwarden.TaskScheduler do
  @moduledoc false

  def build_tasks(prompt, worker_count) when is_binary(prompt) do
    total = max(worker_count, 1)

    for idx <- 1..total do
      %{
        id: Integer.to_string(idx),
        title: task_title(prompt, idx, total),
        payload: %{"prompt" => prompt, "slot" => idx, "slots" => total},
        status: "pending",
        assigned_worker: nil,
        result_summary: nil,
        error: nil
      }
    end
  end

  def next_pending_task(tasks) when is_list(tasks) do
    Enum.find(tasks, &(&1.status == "pending"))
  end

  def assign_task(tasks, task_id, worker_id) do
    update_task(tasks, task_id, fn task ->
      %{task | status: "running", assigned_worker: worker_id}
    end)
  end

  def complete_task(tasks, task_id, summary) do
    update_task(tasks, task_id, fn task ->
      %{task | status: "completed", result_summary: summary}
    end)
  end

  def fail_task(tasks, task_id, error) do
    update_task(tasks, task_id, fn task ->
      %{task | status: "failed", error: error}
    end)
  end

  def counts(tasks) when is_list(tasks) do
    Enum.reduce(tasks, %{pending: 0, running: 0, completed: 0, failed: 0}, fn task, acc ->
      case task.status do
        "pending" -> %{acc | pending: acc.pending + 1}
        "running" -> %{acc | running: acc.running + 1}
        "completed" -> %{acc | completed: acc.completed + 1}
        "failed" -> %{acc | failed: acc.failed + 1}
        _ -> acc
      end
    end)
  end

  defp update_task(tasks, task_id, updater) do
    Enum.map(tasks, fn task ->
      if task.id == task_id, do: updater.(task), else: task
    end)
  end

  defp task_title(prompt, _idx, 1), do: prompt
  defp task_title(prompt, idx, total), do: "#{prompt} [#{idx}/#{total}]"
end
