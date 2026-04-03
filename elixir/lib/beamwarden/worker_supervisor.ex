defmodule Beamwarden.WorkerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  @default_worker_heartbeat_timeout_seconds 30

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker(run_id, opts \\ []) do
    worker_index = list_live_workers(run_id: run_id) |> length() |> Kernel.+(1)

    worker_id =
      Keyword.get_lazy(opts, :worker_id, fn ->
        "#{run_id}-worker-#{worker_index}"
      end)

    start_opts =
      opts
      |> Keyword.put(:worker_id, worker_id)
      |> Keyword.put(:run_id, run_id)

    case DynamicSupervisor.start_child(__MODULE__, {Beamwarden.ExternalWorker, start_opts}) do
      {:ok, _pid} -> {:ok, worker_id}
      {:error, {:already_started, _pid}} -> {:ok, worker_id}
      other -> other
    end
  end

  def list_workers(opts \\ []) do
    run_id = Keyword.get(opts, :run_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    live =
      list_live_workers(run_id: run_id)
      |> Map.new(fn snapshot -> {value(snapshot, :worker_id), snapshot} end)

    persisted =
      Beamwarden.WorkerStore.list(run_id: run_id)
      |> Map.new(fn snapshot -> {value(snapshot, :worker_id), snapshot} end)

    Map.keys(Map.merge(persisted, live))
    |> Enum.map(fn worker_id ->
      live_snapshot = Map.get(live, worker_id)
      persisted_snapshot = Map.get(persisted, worker_id)
      preferred = live_snapshot || persisted_snapshot || %{}
      health = worker_health(preferred, live_snapshot, persisted_snapshot, now)

      preferred
      |> Map.merge(health)
      |> Map.put(:worker_id, worker_id)
      |> Map.put(:presence, if(is_map(live_snapshot), do: "active", else: "persisted"))
      |> Map.put(:active, is_map(live_snapshot))
      |> Map.put(:runtime_state, value(live_snapshot, :state))
      |> Map.put(:active_current_task_id, value(live_snapshot, :current_task_id))
      |> Map.put(
        :persisted_state,
        value(live_snapshot, :persisted_state) || value(persisted_snapshot, :state)
      )
      |> Map.put(
        :persisted_current_task_id,
        value(live_snapshot, :persisted_current_task_id) ||
          value(persisted_snapshot, :current_task_id)
      )
      |> Map.put(
        :last_task_status,
        value(preferred, :last_task_status) || value(persisted_snapshot, :last_task_status)
      )
    end)
    |> Enum.sort_by(&value(&1, :worker_id))
  end

  def list_live_workers(opts \\ []) do
    run_id = Keyword.get(opts, :run_id)

    Beamwarden.ExternalWorkerRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn worker_id ->
      try do
        [Beamwarden.ExternalWorker.snapshot(worker_id)]
      catch
        :exit, _reason -> []
      end
    end)
    |> Enum.filter(fn snapshot ->
      is_nil(run_id) or value(snapshot, :run_id) == run_id
    end)
    |> Enum.sort_by(&value(&1, :worker_id))
  end

  def worker_pid(worker_id) do
    case Registry.lookup(Beamwarden.ExternalWorkerRegistry, worker_id) do
      [{pid, _value} | _] -> {:ok, pid}
      [] -> :error
    end
  end

  defp value(nil, _key), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp worker_health(preferred, _live_snapshot, persisted_snapshot, now) do
    heartbeat_at = value(preferred, :heartbeat_at) || value(persisted_snapshot, :heartbeat_at)

    case heartbeat_window(heartbeat_at, now) do
      {:ok, %{age_seconds: age_seconds, timeout_at: timeout_at}, stale?} ->
        %{
          heartbeat_at: heartbeat_at,
          heartbeat_age_seconds: age_seconds,
          heartbeat_timeout_at: DateTime.to_iso8601(timeout_at),
          health_state: if(stale?, do: "stale", else: "active"),
          health_reason: if(stale?, do: "heartbeat_expired", else: "heartbeat_recent")
        }

      {:error, :missing} ->
        %{
          heartbeat_at: nil,
          heartbeat_age_seconds: nil,
          heartbeat_timeout_at: nil,
          health_state: "stale",
          health_reason: "heartbeat_missing"
        }

      {:error, :invalid} ->
        %{
          heartbeat_at: heartbeat_at,
          heartbeat_age_seconds: nil,
          heartbeat_timeout_at: nil,
          health_state: "stale",
          health_reason: "heartbeat_invalid"
        }
    end
  end

  defp heartbeat_window(nil, _now), do: {:error, :missing}

  defp heartbeat_window(heartbeat_at, now) do
    with {:ok, heartbeat_at, _offset} <- DateTime.from_iso8601(heartbeat_at) do
      timeout_at = DateTime.add(heartbeat_at, worker_heartbeat_timeout_seconds(), :second)

      {:ok,
       %{age_seconds: max(DateTime.diff(now, heartbeat_at, :second), 0), timeout_at: timeout_at},
       DateTime.compare(timeout_at, now) == :lt}
    else
      _ -> {:error, :invalid}
    end
  end

  defp worker_heartbeat_timeout_seconds do
    Application.get_env(
      :beamwarden,
      :worker_heartbeat_timeout_seconds,
      @default_worker_heartbeat_timeout_seconds
    )
  end
end
