defmodule Beamwarden.MirroredCommand do
  @moduledoc false
  defstruct [:name, :source_hint]

  def execute(%__MODULE__{} = command, prompt) do
    Beamwarden.Commands.execute_command(command.name, prompt).message
  end
end

defmodule Beamwarden.MirroredTool do
  @moduledoc false
  defstruct [:name, :source_hint]

  def execute(%__MODULE__{} = tool, payload) do
    Beamwarden.Tools.execute_tool(tool.name, payload).message
  end
end

defmodule Beamwarden.ExecutionRegistry do
  @moduledoc false
  defstruct commands: [], tools: []

  def command(%__MODULE__{commands: commands}, name) do
    Enum.find(commands, &(String.downcase(&1.name) == String.downcase(name)))
  end

  def tool(%__MODULE__{tools: tools}, name) do
    Enum.find(tools, &(String.downcase(&1.name) == String.downcase(name)))
  end
end

defmodule Beamwarden.ExecutionRegistryBuilder do
  @moduledoc false

  def build do
    %Beamwarden.ExecutionRegistry{
      commands:
        Enum.map(
          Beamwarden.Commands.ported_commands(),
          &%Beamwarden.MirroredCommand{name: &1.name, source_hint: &1.source_hint}
        ),
      tools:
        Enum.map(
          Beamwarden.Tools.ported_tools(),
          &%Beamwarden.MirroredTool{name: &1.name, source_hint: &1.source_hint}
        )
    }
  end
end
