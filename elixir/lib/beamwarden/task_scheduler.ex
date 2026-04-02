defmodule Beamwarden.TaskScheduler do
  @moduledoc false

  def build_initial_tasks(run_id, prompt) do
    now = now()

    [
      %{
        task_id: "#{run_id}-task-1",
        run_id: run_id,
        title: summarize_prompt(prompt),
        payload: prompt,
        attempt: 1,
        status: "pending",
        assigned_worker: nil,
        result_summary: nil,
        error: nil,
        created_at: now,
        updated_at: now
      }
    ]
  end

  def assign_next_task(tasks, worker_id) do
    case Enum.find(tasks, &(value(&1, :status) == "pending")) do
      nil ->
        :none

      task ->
        updated =
          update_task(tasks, value(task, :task_id), fn current ->
            current
            |> put(:status, "in_progress")
            |> put(:assigned_worker, worker_id)
            |> put(:updated_at, now())
          end)

        {:ok, normalize(task) |> put(:status, "in_progress") |> put(:assigned_worker, worker_id),
         updated}
    end
  end

  def complete_task(tasks, task_id, worker_id, summary) do
    update_task(tasks, task_id, fn task ->
      task
      |> put(:status, "completed")
      |> put(:assigned_worker, worker_id)
      |> put(:result_summary, blank_to_nil(summary))
      |> put(:error, nil)
      |> put(:updated_at, now())
    end)
  end

  def fail_task(tasks, task_id, worker_id, error) do
    update_task(tasks, task_id, fn task ->
      task
      |> put(:status, "failed")
      |> put(:assigned_worker, worker_id)
      |> put(:error, blank_to_nil(error) || "worker failed")
      |> put(:updated_at, now())
    end)
  end

  def cancel_running_tasks(tasks) do
    {updated, cancelled_count} =
      Enum.map_reduce(tasks, 0, fn task, cancelled_count ->
        status = value(task, :status)

        if status in ["pending", "in_progress"] do
          {
            normalize(task)
            |> put(:status, "cancelled")
            |> put(:result_summary, nil)
            |> put(:error, nil)
            |> put(:updated_at, now()),
            cancelled_count + 1
          }
        else
          {normalize(task), cancelled_count}
        end
      end)

    {updated, cancelled_count}
  end

  def retry_task(tasks, task_id) do
    case Enum.find(tasks, &(value(&1, :task_id) == task_id)) do
      nil ->
        {:error, :not_found}

      task ->
        if value(task, :status) in ["failed", "cancelled"] do
          retried_task =
            normalize(task)
            |> put(:attempt, (value(task, :attempt) || 1) + 1)
            |> put(:status, "pending")
            |> put(:assigned_worker, nil)
            |> put(:result_summary, nil)
            |> put(:error, nil)
            |> put(:updated_at, now())

          updated =
            update_task(tasks, task_id, fn _current ->
              retried_task
            end)

          {:ok, retried_task, updated}
        else
          {:error, :not_retryable}
        end
    end
  end

  def status(tasks, worker_count, opts \\ []) do
    lifecycle = Keyword.get(opts, :lifecycle, :active)

    cond do
      tasks == [] ->
        if lifecycle == :cancelled, do: "cancelled", else: "pending"

      lifecycle == :cancelled and terminal?(tasks) ->
        "cancelled"

      Enum.any?(tasks, &(value(&1, :status) == "failed")) and terminal?(tasks) ->
        "failed"

      terminal?(tasks) ->
        "completed"

      Enum.any?(tasks, &(value(&1, :status) == "in_progress")) ->
        "running"

      worker_count == 0 ->
        "pending"

      true ->
        "running"
    end
  end

  def counts(tasks) do
    %{
      task_count: length(tasks),
      pending_count: Enum.count(tasks, &(value(&1, :status) == "pending")),
      running_count: Enum.count(tasks, &(value(&1, :status) == "in_progress")),
      completed_count: Enum.count(tasks, &(value(&1, :status) == "completed")),
      failed_count: Enum.count(tasks, &(value(&1, :status) == "failed")),
      cancelled_count: Enum.count(tasks, &(value(&1, :status) == "cancelled"))
    }
  end

  def terminal?(tasks) do
    tasks != [] and
      Enum.all?(tasks, &(value(&1, :status) in ["completed", "failed", "cancelled"]))
  end

  defp update_task(tasks, task_id, updater) do
    Enum.map(tasks, fn task ->
      if value(task, :task_id) == task_id, do: updater.(normalize(task)), else: normalize(task)
    end)
  end

  defp summarize_prompt(prompt) do
    prompt
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.slice(0, 72)
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp normalize(task) do
    %{
      task_id: value(task, :task_id),
      run_id: value(task, :run_id),
      title: value(task, :title),
      payload: value(task, :payload),
      attempt: value(task, :attempt) || 1,
      status: value(task, :status),
      assigned_worker: value(task, :assigned_worker),
      result_summary: value(task, :result_summary),
      error: value(task, :error),
      created_at: value(task, :created_at),
      updated_at: value(task, :updated_at)
    }
  end

  defp put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
