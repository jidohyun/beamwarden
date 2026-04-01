defmodule Beamwarden.ToolPool do
  @moduledoc false

  def as_markdown do
    tools = Beamwarden.Tools.get_tools()

    [
      "# Tool Pool",
      "",
      "Total mirrored tool entries: #{length(tools)}",
      "",
      "Representative entries:",
      Enum.take(tools, 10) |> Enum.map(&"- #{&1.name} — #{&1.source_hint}")
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
