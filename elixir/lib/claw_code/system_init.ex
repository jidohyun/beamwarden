defmodule ClawCode.SystemInit do
  @moduledoc false

  def build(trusted \\ true) do
    setup = ClawCode.Setup.run(ClawCode.repo_root(), trusted)
    commands = ClawCode.Commands.get_commands()
    tools = ClawCode.Tools.get_tools()

    [
      "# System Init",
      "",
      "Trusted: #{setup.trusted}",
      "Built-in command names: #{MapSet.size(ClawCode.Commands.built_in_command_names())}",
      "Loaded command entries: #{length(commands)}",
      "Loaded tool entries: #{length(tools)}",
      "",
      "Startup steps:",
      Enum.map(ClawCode.WorkspaceSetup.startup_steps(), &"- #{&1}")
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end
