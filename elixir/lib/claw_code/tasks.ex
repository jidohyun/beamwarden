defmodule ClawCode.Tasks do
  @moduledoc false

  alias ClawCode.PortingTask

  def default_tasks do
    build_default_backlog()
  end

  def from_descriptions(descriptions) do
    Enum.map(descriptions, fn description ->
      %PortingTask{
        id: slug(description),
        title: description,
        description: description
      }
    end)
  end

  def build_default_backlog do
    [
      %PortingTask{
        id: "session-control-plane",
        title: "Supervised session orchestration",
        description: "Keep resumable session state inside OTP processes."
      },
      %PortingTask{
        id: "workflow-control-plane",
        title: "Workflow/task orchestration",
        description: "Coordinate long-running task state with OTP processes."
      },
      %PortingTask{
        id: "mirror-surface",
        title: "Mirror remaining Python surface concepts",
        description: "Preserve the clean-room mirror shape in Elixir modules."
      }
    ]
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
