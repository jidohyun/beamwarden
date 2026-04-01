defmodule ClawCode.MirroredCommand do
  @moduledoc false
  defstruct [:name, :source_hint]

  def execute(%__MODULE__{} = command, prompt) do
    ClawCode.Commands.execute_command(command.name, prompt).message
  end
end

defmodule ClawCode.MirroredTool do
  @moduledoc false
  defstruct [:name, :source_hint]

  def execute(%__MODULE__{} = tool, payload) do
    ClawCode.Tools.execute_tool(tool.name, payload).message
  end
end

defmodule ClawCode.ExecutionRegistry do
  @moduledoc false
  defstruct commands: [], tools: []

  def command(%__MODULE__{commands: commands}, name) do
    Enum.find(commands, &(String.downcase(&1.name) == String.downcase(name)))
  end

  def tool(%__MODULE__{tools: tools}, name) do
    Enum.find(tools, &(String.downcase(&1.name) == String.downcase(name)))
  end
end

defmodule ClawCode.ExecutionRegistryBuilder do
  @moduledoc false

  def build do
    %ClawCode.ExecutionRegistry{
      commands:
        Enum.map(
          ClawCode.Commands.ported_commands(),
          &%ClawCode.MirroredCommand{name: &1.name, source_hint: &1.source_hint}
        ),
      tools:
        Enum.map(
          ClawCode.Tools.ported_tools(),
          &%ClawCode.MirroredTool{name: &1.name, source_hint: &1.source_hint}
        )
    }
  end
end
