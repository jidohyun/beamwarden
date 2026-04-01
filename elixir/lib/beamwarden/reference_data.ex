defmodule Beamwarden.ReferenceData do
  @moduledoc false

  def archive_surface_snapshot do
    read_json("archive_surface_snapshot.json")
  end

  def commands_snapshot do
    read_json("commands_snapshot.json")
  end

  def tools_snapshot do
    read_json("tools_snapshot.json")
  end

  def subsystem_snapshots do
    Beamwarden.subsystem_snapshot_root()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      %{
        name: Path.basename(path, ".json"),
        sample_files: read_json(path)
      }
    end)
  end

  defp read_json(name) when is_binary(name) do
    path =
      if String.contains?(name, "/") do
        name
      else
        Path.join(Beamwarden.reference_data_root(), name)
      end

    read_json_path(path)
  end

  defp read_json_path(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end
end
