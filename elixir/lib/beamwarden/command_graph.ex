defmodule Beamwarden.CommandGraph do
  @moduledoc false

  def as_markdown do
    commands = Beamwarden.Commands.ported_commands()

    [
      "# Command Graph",
      "",
      "Total mirrored command entries: #{length(commands)}",
      "",
      "Representative entries:",
      Enum.take(commands, 10) |> Enum.map(&"- #{&1.name} — #{&1.source_hint}")
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
