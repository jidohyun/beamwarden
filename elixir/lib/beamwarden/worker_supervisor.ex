defmodule Beamwarden.WorkerSupervisor do
  @moduledoc false

  use DynamicSupervisor

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

      preferred
      |> Map.put(:worker_id, worker_id)
      |> Map.put(:presence, if(is_map(live_snapshot), do: "active", else: "persisted"))
      |> Map.put(:active, is_map(live_snapshot))
      |> Map.put(:runtime_state, value(live_snapshot, :state))
      |> Map.put(:persisted_state, value(persisted_snapshot, :state))
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
    |> Enum.map(&Beamwarden.ExternalWorker.snapshot/1)
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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
