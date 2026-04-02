defmodule Beamwarden.RunStore do
  @moduledoc false

  def save(snapshot) do
    File.mkdir_p!(Beamwarden.run_root())
    path = Beamwarden.run_path(value(snapshot, :run_id))
    File.write!(path, JSON.encode!(snapshot))
    path
  end

  def load(run_id) do
    path = Beamwarden.run_path(run_id)

    case File.read(path) do
      {:ok, contents} -> {:ok, JSON.decode!(contents)}
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  def list do
    Beamwarden.run_root()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&load_file/1)
    |> Enum.sort_by(&value(&1, :run_id))
  end

  def delete(run_id) do
    Beamwarden.run_path(run_id)
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  defp load_file(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
