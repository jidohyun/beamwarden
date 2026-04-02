defmodule Beamwarden.WorkerStore do
  @moduledoc false

  def save(snapshot) do
    File.mkdir_p!(Beamwarden.worker_root())
    path = Beamwarden.worker_path(value(snapshot, :worker_id))
    File.write!(path, JSON.encode!(snapshot))
    path
  end

  def load(worker_id) do
    path = Beamwarden.worker_path(worker_id)

    case File.read(path) do
      {:ok, contents} -> {:ok, JSON.decode!(contents)}
      {:error, :enoent} -> :error
    end
  end

  def list(opts \\ []) do
    run_id = Keyword.get(opts, :run_id)

    Beamwarden.worker_root()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&load_file/1)
    |> Enum.filter(fn snapshot ->
      is_nil(run_id) or value(snapshot, :run_id) == run_id
    end)
    |> Enum.sort_by(&value(&1, :worker_id))
  end

  def delete(worker_id) do
    case File.rm(Beamwarden.worker_path(worker_id)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_file(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
