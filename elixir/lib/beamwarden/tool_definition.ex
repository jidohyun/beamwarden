defmodule Beamwarden.ToolDefinition do
  @moduledoc false
  defstruct [:name, :purpose]

  def default_tools do
    [
      %__MODULE__{name: "port_manifest", purpose: "Summarize the active Elixir workspace"},
      %__MODULE__{name: "query_engine", purpose: "Render an Elixir-first porting summary"},
      %__MODULE__{name: "control_plane", purpose: "Inspect supervised sessions and workflows"}
    ]
  end

  def as_lines(tool_defs) do
    Enum.map(tool_defs, &"- #{&1.name}: #{&1.purpose}")
  end
end
