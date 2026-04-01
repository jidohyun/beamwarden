defmodule Beamwarden.PortingTask do
  @moduledoc false

  defstruct [:id, :title, :description, :detail, status: "pending", priority: 1, metadata: %{}]

  def complete(%__MODULE__{} = task, metadata \\ %{}) do
    %{task | status: "completed", metadata: Map.merge(task.metadata, Map.new(metadata))}
  end

  def as_line(%__MODULE__{} = task) do
    label = task.title || task.description || task.id
    "[#{task.status}] #{task.id || "task"} — #{label}"
  end
end
