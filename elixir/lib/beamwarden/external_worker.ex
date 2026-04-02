defmodule Beamwarden.ExternalWorker do
  @moduledoc false

  use GenServer

  defstruct [
    :worker_id,
    :run_id,
    :command,
    :executor,
    :current_task_id,
    :last_result_summary,
    :last_task_status,
    :started_at,
    :heartbeat_at,
    :last_event_at,
    state: "idle"
  ]

  def child_spec(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)

    %{
      id: {__MODULE__, worker_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    GenServer.start_link(__MODULE__, opts, name: via(worker_id))
  end

  def assign(worker_id, task) do
    GenServer.cast(via(worker_id), {:assign, task})
  end

  def snapshot(worker_id) do
    GenServer.call(via(worker_id), :snapshot)
  end

  @impl true
  def init(opts) do
    now = now()

    state = %__MODULE__{
      worker_id: Keyword.fetch!(opts, :worker_id),
      run_id: Keyword.fetch!(opts, :run_id),
      command: Keyword.get(opts, :command),
      executor: Keyword.get(opts, :executor),
      started_at: now,
      heartbeat_at: now,
      last_event_at: now
    }

    persist(state)
    {:ok, state}
  end

  @impl true
  def handle_cast({:assign, task}, %__MODULE__{state: "idle"} = state) do
    busy_state =
      state
      |> Map.put(:state, "busy")
      |> Map.put(:current_task_id, value(task, :task_id))
      |> Map.put(:heartbeat_at, now())
      |> Map.put(:last_event_at, now())
      |> persist()

    send(self(), {:execute, task})
    {:noreply, busy_state}
  end

  @impl true
  def handle_cast({:assign, _task}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def handle_info({:execute, task}, %__MODULE__{} = state) do
    task_id = value(task, :task_id)
    attempt = value(task, :attempt) || 1

    next_state =
      case execute_task(task, state) do
        {:ok, summary} ->
          Beamwarden.RunServer.worker_result(
            state.run_id,
            state.worker_id,
            task_id,
            attempt,
            {:ok, summary}
          )

          state
          |> Map.put(:state, "idle")
          |> Map.put(:current_task_id, nil)
          |> Map.put(:last_result_summary, summary)
          |> Map.put(:last_task_status, "completed")
          |> Map.put(:heartbeat_at, now())
          |> Map.put(:last_event_at, now())
          |> persist()

        {:error, error} ->
          Beamwarden.RunServer.worker_result(
            state.run_id,
            state.worker_id,
            task_id,
            attempt,
            {:error, error}
          )

          state
          |> Map.put(:state, "idle")
          |> Map.put(:current_task_id, nil)
          |> Map.put(:last_result_summary, error)
          |> Map.put(:last_task_status, "failed")
          |> Map.put(:heartbeat_at, now())
          |> Map.put(:last_event_at, now())
          |> persist()
      end

    {:noreply, next_state}
  end

  defp execute_task(task, %__MODULE__{executor: executor}) when is_function(executor, 1) do
    executor.(normalize_task(task))
  end

  defp execute_task(task, %__MODULE__{command: command}) when is_binary(command) do
    run_command(command, task)
  end

  defp execute_task(task, %__MODULE__{}) do
    run_command("printf '%s\\n' \"$BEAMWARDEN_TASK_PAYLOAD\"", task)
  end

  defp run_command(command, task) do
    env = [
      {"BEAMWARDEN_TASK_ID", value(task, :task_id) || ""},
      {"BEAMWARDEN_RUN_ID", value(task, :run_id) || ""},
      {"BEAMWARDEN_TASK_TITLE", value(task, :title) || ""},
      {"BEAMWARDEN_TASK_ATTEMPT", Integer.to_string(value(task, :attempt) || 1)},
      {"BEAMWARDEN_TASK_PAYLOAD", value(task, :payload) || ""}
    ]

    {output, exit_status} =
      System.cmd("sh", ["-lc", command], env: env, stderr_to_stdout: true)

    cleaned = output |> String.trim() |> blank_to_nil()

    if exit_status == 0 do
      {:ok, cleaned || value(task, :title) || value(task, :task_id)}
    else
      {:error, cleaned || "command exited with status #{exit_status}"}
    end
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      worker_id: state.worker_id,
      run_id: state.run_id,
      state: state.state,
      current_task_id: state.current_task_id,
      last_task_status: state.last_task_status,
      started_at: state.started_at,
      heartbeat_at: state.heartbeat_at,
      last_event_at: state.last_event_at,
      last_result_summary: state.last_result_summary
    }
  end

  defp normalize_task(task) do
    %{
      task_id: value(task, :task_id),
      run_id: value(task, :run_id),
      title: value(task, :title),
      attempt: value(task, :attempt) || 1,
      payload: value(task, :payload)
    }
  end

  defp persist(%__MODULE__{} = state) do
    Beamwarden.WorkerStore.save(snapshot_map(state))
    state
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp via(worker_id), do: {:via, Registry, {Beamwarden.ExternalWorkerRegistry, worker_id}}
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
