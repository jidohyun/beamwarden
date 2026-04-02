defmodule Beamwarden.RunServer do
  @moduledoc false

  use GenServer

  alias Beamwarden.TaskScheduler

  defstruct [
    :run_id,
    :prompt,
    :created_at,
    :updated_at,
    :worker_opts,
    :lifecycle,
    :last_status,
    tasks: [],
    worker_ids: []
  ]

  def child_spec(opts) do
    run_id = Keyword.fetch!(opts, :run_id)

    %{
      id: {__MODULE__, run_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  def snapshot(run_id) do
    GenServer.call(via(run_id), :snapshot)
  end

  def running?(run_id) do
    Registry.lookup(Beamwarden.RunRegistry, run_id) != []
  end

  def worker_result(run_id, worker_id, task_id, result) do
    worker_result(run_id, worker_id, task_id, 1, result)
  end

  def worker_result(run_id, worker_id, task_id, attempt, result) do
    GenServer.cast(via(run_id), {:worker_result, worker_id, task_id, attempt, result})
  end

  def cancel(run_id) do
    GenServer.call(via(run_id), :cancel_run)
  end

  def retry_task(run_id, task_id) do
    GenServer.call(via(run_id), {:retry_task, task_id})
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    prompt = Keyword.fetch!(opts, :prompt)
    worker_count = max(Keyword.get(opts, :workers, 1), 0)
    now = now()

    state = %__MODULE__{
      run_id: run_id,
      prompt: prompt,
      tasks: TaskScheduler.build_initial_tasks(run_id, prompt),
      created_at: now,
      updated_at: now,
      lifecycle: :active,
      worker_opts: Keyword.get(opts, :worker_opts, [])
    }

    log_event(run_id, %{type: "run_started", prompt: prompt})
    Enum.each(state.tasks, &log_task_created(run_id, &1))

    worker_ids =
      if worker_count > 0 do
        Enum.map(1..worker_count, fn index ->
          {:ok, worker_id} =
            Beamwarden.WorkerSupervisor.start_worker(
              run_id,
              Keyword.merge(state.worker_opts, worker_id: "#{run_id}-worker-#{index}")
            )

          worker_id
        end)
      else
        []
      end

    Enum.each(worker_ids, &log_event(run_id, %{type: "worker_spawned", worker_id: &1}))

    next_state = persist(%{state | worker_ids: worker_ids})
    send(self(), :dispatch)
    {:ok, next_state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def handle_call(:cancel_run, _from, %__MODULE__{} = state) do
    {tasks, cancelled_count} = TaskScheduler.cancel_running_tasks(state.tasks)

    if cancelled_count == 0 do
      {:reply, {:error, :not_cancelable}, state}
    else
      next_state =
        state
        |> Map.put(:tasks, tasks)
        |> Map.put(:lifecycle, :cancelled)
        |> Map.put(:updated_at, now())
        |> persist()

      {:reply, {:ok, snapshot_map(next_state)}, next_state}
    end
  end

  @impl true
  def handle_call({:retry_task, task_id}, _from, %__MODULE__{} = state) do
    case TaskScheduler.retry_task(state.tasks, task_id) do
      {:ok, retried_task, tasks} ->
        log_event(state.run_id, %{
          type: "task_retried",
          task_id: task_id,
          attempt: value(retried_task, :attempt)
        })

        next_state =
          state
          |> Map.put(:tasks, tasks)
          |> Map.put(:lifecycle, :active)
          |> Map.put(:updated_at, now())
          |> persist()

        send(self(), :dispatch)
        {:reply, {:ok, snapshot_map(next_state)}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:worker_result, worker_id, task_id, attempt, result}, %__MODULE__{} = state) do
    next_state = handle_worker_result(state, worker_id, task_id, attempt, result)
    send(self(), :dispatch)
    {:noreply, next_state}
  end

  @impl true
  def handle_info(:dispatch, %__MODULE__{} = state) do
    {tasks, assigned?} =
      Beamwarden.WorkerSupervisor.list_live_workers(run_id: state.run_id)
      |> Enum.filter(&(value(&1, :state) == "idle"))
      |> Enum.reduce({state.tasks, false}, fn worker, {tasks, assigned?} ->
        worker_id = value(worker, :worker_id)

        case TaskScheduler.assign_next_task(tasks, worker_id) do
          {:ok, task, updated_tasks} ->
            Beamwarden.ExternalWorker.assign(worker_id, task)

            log_event(state.run_id, %{
              type: "task_assigned",
              task_id: value(task, :task_id),
              worker_id: worker_id,
              attempt: value(task, :attempt) || 1
            })

            {updated_tasks, true}

          :none ->
            {tasks, assigned?}
        end
      end)

    next_state =
      if assigned? do
        state
        |> Map.put(:tasks, tasks)
        |> Map.put(:updated_at, now())
        |> persist()
      else
        state
      end

    {:noreply, next_state}
  end

  defp persist(%__MODULE__{} = state) do
    snapshot = snapshot_map(state)
    Beamwarden.RunStore.save(snapshot)
    maybe_log_run_transition(state.last_status, value(snapshot, :status), snapshot)
    %{state | updated_at: value(snapshot, :updated_at), last_status: value(snapshot, :status)}
  end

  defp snapshot_map(%__MODULE__{} = state) do
    counts = TaskScheduler.counts(state.tasks)

    %{
      run_id: state.run_id,
      prompt: state.prompt,
      status:
        TaskScheduler.status(state.tasks, length(state.worker_ids), lifecycle: state.lifecycle),
      lifecycle: Atom.to_string(state.lifecycle || :active),
      created_at: state.created_at,
      updated_at: state.updated_at || now(),
      task_ids: Enum.map(state.tasks, &value(&1, :task_id)),
      worker_ids: state.worker_ids,
      tasks: Enum.map(state.tasks, &normalize_task/1),
      task_count: counts.task_count,
      pending_count: counts.pending_count,
      running_count: counts.running_count,
      completed_count: counts.completed_count,
      failed_count: counts.failed_count,
      cancelled_count: counts.cancelled_count
    }
  end

  defp normalize_task(task) do
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

  defp via(run_id), do: {:via, Registry, {Beamwarden.RunRegistry, run_id}}
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp handle_worker_result(%__MODULE__{} = state, worker_id, task_id, attempt, {:ok, summary}) do
    with {:ok, task} <- fetch_current_task(state.tasks, task_id),
         :ok <- ensure_current_attempt(task, attempt) do
      log_event(state.run_id, %{
        type: "task_completed",
        task_id: task_id,
        worker_id: worker_id,
        attempt: attempt,
        summary: blank_to_nil(summary)
      })

      state
      |> Map.put(:tasks, TaskScheduler.complete_task(state.tasks, task_id, worker_id, summary))
      |> Map.put(:updated_at, now())
      |> persist()
    else
      {:error, reason} ->
        log_ignored_result(state.run_id, worker_id, task_id, attempt, :ok, reason)
        state
    end
  end

  defp handle_worker_result(%__MODULE__{} = state, worker_id, task_id, attempt, {:error, error}) do
    with {:ok, task} <- fetch_current_task(state.tasks, task_id),
         :ok <- ensure_current_attempt(task, attempt) do
      log_event(state.run_id, %{
        type: "task_failed",
        task_id: task_id,
        worker_id: worker_id,
        attempt: attempt,
        error: blank_to_nil(error) || "worker failed"
      })

      state
      |> Map.put(:tasks, TaskScheduler.fail_task(state.tasks, task_id, worker_id, error))
      |> Map.put(:updated_at, now())
      |> persist()
    else
      {:error, reason} ->
        log_ignored_result(state.run_id, worker_id, task_id, attempt, :error, reason)
        state
    end
  end

  defp fetch_current_task(tasks, task_id) do
    case Enum.find(tasks, &(value(&1, :task_id) == task_id)) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  defp ensure_current_attempt(task, attempt) do
    cond do
      value(task, :status) != "in_progress" -> {:error, :stale_status}
      (value(task, :attempt) || 1) != attempt -> {:error, :stale_attempt}
      true -> :ok
    end
  end

  defp log_task_created(run_id, task) do
    log_event(run_id, %{
      type: "task_created",
      task_id: value(task, :task_id),
      title: value(task, :title),
      attempt: value(task, :attempt) || 1
    })
  end

  defp maybe_log_run_transition(previous, current, _snapshot)
       when previous == current or current in ["pending", "running"] do
    :ok
  end

  defp maybe_log_run_transition(_previous, "completed", snapshot) do
    log_event(value(snapshot, :run_id), %{
      type: "run_completed",
      completed_count: value(snapshot, :completed_count),
      failed_count: value(snapshot, :failed_count),
      cancelled_count: value(snapshot, :cancelled_count)
    })
  end

  defp maybe_log_run_transition(_previous, "failed", snapshot) do
    log_event(value(snapshot, :run_id), %{
      type: "run_failed",
      completed_count: value(snapshot, :completed_count),
      failed_count: value(snapshot, :failed_count),
      cancelled_count: value(snapshot, :cancelled_count)
    })
  end

  defp maybe_log_run_transition(_previous, "cancelled", snapshot) do
    log_event(value(snapshot, :run_id), %{
      type: "run_cancelled",
      completed_count: value(snapshot, :completed_count),
      failed_count: value(snapshot, :failed_count),
      cancelled_count: value(snapshot, :cancelled_count)
    })
  end

  defp log_ignored_result(run_id, worker_id, task_id, attempt, result, reason) do
    log_event(run_id, %{
      type: "worker_result_ignored",
      worker_id: worker_id,
      task_id: task_id,
      attempt: attempt,
      result: Atom.to_string(result),
      reason: Atom.to_string(reason)
    })
  end

  defp log_event(run_id, event) do
    Beamwarden.EventStore.append(run_id, event)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
