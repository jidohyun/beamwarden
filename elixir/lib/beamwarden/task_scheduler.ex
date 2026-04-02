defmodule Beamwarden.TaskScheduler do
  @moduledoc false

  @terminal_statuses ["completed", "failed"]

  def initial_tasks(run_id, prompt) do
    prompt
    |> split_prompt()
    |> Enum.with_index(1)
    |> Enum.map(fn {payload, index} ->
      now = timestamp()

      %{
        task_id: Integer.to_string(index),
        run_id: run_id,
        title: task_title(payload, index),
        payload: payload,
        status: "pending",
        assigned_worker: nil,
        result_summary: nil,
        error: nil,
        created_at: now,
        updated_at: now
      }
    end)
  end

  def assign_next_task(tasks, worker_id) do
    case Enum.find_index(tasks, &(&1.status == "pending")) do
      nil ->
        {:none, tasks}

      index ->
        task = Enum.at(tasks, index)
        now = timestamp()

        assigned = %{
          task
          | status: "running",
            assigned_worker: worker_id,
            updated_at: now,
            error: nil
        }

        {assigned, List.replace_at(tasks, index, assigned)}
    end
  end

  def finish_task(tasks, task_id, worker_id, {:ok, result_summary}) do
    update_task(tasks, task_id, fn task ->
      %{
        task
        | status: "completed",
          assigned_worker: worker_id,
          result_summary: result_summary,
          error: nil,
          updated_at: timestamp()
      }
    end)
  end

  def finish_task(tasks, task_id, worker_id, {:error, error}) do
    update_task(tasks, task_id, fn task ->
      %{
        task
        | status: "failed",
          assigned_worker: worker_id,
          result_summary: nil,
          error: error,
          updated_at: timestamp()
      }
    end)
  end

  def counts(tasks) do
    grouped = Enum.frequencies_by(tasks, & &1.status)

    %{
      task_count: length(tasks),
      pending_count: Map.get(grouped, "pending", 0),
      running_count: Map.get(grouped, "running", 0),
      completed_count: Map.get(grouped, "completed", 0),
      failed_count: Map.get(grouped, "failed", 0)
    }
  end

  def terminal?(tasks) do
    Enum.all?(tasks, &(&1.status in @terminal_statuses))
  end

  def run_status(tasks) do
    counts = counts(tasks)

    cond do
      counts.task_count == 0 -> "completed"
      counts.running_count > 0 -> "running"
      counts.pending_count > 0 -> "running"
      counts.failed_count > 0 -> "failed"
      true -> "completed"
    end
  end

  defp split_prompt(prompt) do
    prompt
    |> String.split(~r/\s*\|\|\s*|\r?\n+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> [String.trim(prompt)]
      items -> items
    end
  end

  defp task_title(payload, index) do
    case payload |> String.trim() |> String.split(~r/\s+/, trim: true) |> Enum.take(6) do
      [] -> "Task #{index}"
      words -> Enum.join(words, " ")
    end
  end

  defp update_task(tasks, task_id, updater) do
    case Enum.find_index(tasks, &(&1.task_id == task_id)) do
      nil -> tasks
      index -> List.update_at(tasks, index, updater)
    end
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
