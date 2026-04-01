defmodule Beamwarden.SystemInit do
  @moduledoc false

  def build(trusted \\ true) do
    setup = Beamwarden.Setup.run(Beamwarden.repo_root(), trusted)
    commands = Beamwarden.Commands.get_commands()
    tools = Beamwarden.Tools.get_tools()

    [
      "# System Init",
      "",
      "Trusted: #{setup.trusted}",
      "Built-in command names: #{MapSet.size(Beamwarden.Commands.built_in_command_names())}",
      "Loaded command entries: #{length(commands)}",
      "Loaded tool entries: #{length(tools)}",
      "",
      "Startup steps:",
      Enum.map(Beamwarden.WorkspaceSetup.startup_steps(), &"- #{&1}")
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
