defmodule ClawCode.WorkflowStore do
  @moduledoc false

  def save(snapshot) do
    File.mkdir_p!(ClawCode.workflow_root())
    path = ClawCode.workflow_path(snapshot.workflow_id)
    File.write!(path, JSON.encode!(snapshot))
    path
  end

  def load(workflow_id) do
    path = ClawCode.workflow_path(workflow_id)

    case File.read(path) do
      {:ok, contents} -> {:ok, JSON.decode!(contents)}
      {:error, :enoent} -> :error
    end
  end
end
