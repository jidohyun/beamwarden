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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
