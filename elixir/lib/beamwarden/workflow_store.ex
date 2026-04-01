defmodule Beamwarden.WorkflowStore do
  @moduledoc false

  def save(snapshot) do
    File.mkdir_p!(Beamwarden.workflow_root())
    path = Beamwarden.workflow_path(snapshot.workflow_id)
    File.write!(path, JSON.encode!(Map.put_new(snapshot, :owner_node, current_owner_node())))
    path
  end

  def load(workflow_id) do
    path = Beamwarden.workflow_path(workflow_id)

    case File.read(path) do
      {:ok, contents} -> {:ok, JSON.decode!(contents)}
      {:error, :enoent} -> :error
    end
  end

  def owner_node(workflow_id) do
    case load(workflow_id) do
      {:ok, snapshot} -> snapshot["owner_node"]
      :error -> nil
    end
  end

  defp current_owner_node do
    if Node.alive?(), do: Atom.to_string(node()), else: nil
  end
end
