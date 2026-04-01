defmodule ClawCode.PortingTask do
  @moduledoc false

  defstruct [:id, :title, :description, status: "pending", priority: 1, metadata: %{}]

  def complete(%__MODULE__{} = task, metadata \\ %{}) do
    %{task | status: "completed", metadata: Map.merge(task.metadata, Map.new(metadata))}
  end
end
