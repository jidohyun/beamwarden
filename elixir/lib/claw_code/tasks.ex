defmodule ClawCode.Tasks do
  @moduledoc false

  alias ClawCode.PortingTask

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
end
