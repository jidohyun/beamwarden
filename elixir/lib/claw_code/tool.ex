defmodule ClawCode.ToolCall do
  @moduledoc false

  defstruct [:name, :payload, :handled, :message]

  def from_execution(%ClawCode.ToolExecution{} = execution) do
    %__MODULE__{
      name: execution.name,
      payload: execution.payload,
      handled: execution.handled,
      message: execution.message
    }
  end
end
