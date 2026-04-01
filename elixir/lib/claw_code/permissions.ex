defmodule ClawCode.ToolPermissionContext do
  @moduledoc false
  defstruct deny_names: MapSet.new(), deny_prefixes: []

  def from_iterables(deny_names \\ [], deny_prefixes \\ []) do
    %__MODULE__{
      deny_names: deny_names |> Enum.map(&String.downcase/1) |> MapSet.new(),
      deny_prefixes: Enum.map(deny_prefixes, &String.downcase/1)
    }
  end

  def blocks?(%__MODULE__{} = context, tool_name) do
    lowered = String.downcase(tool_name)
    MapSet.member?(context.deny_names, lowered) or
      Enum.any?(context.deny_prefixes, &String.starts_with?(lowered, &1))
  end
end
