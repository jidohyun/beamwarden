defmodule Beamwarden.ToolExecution do
  @moduledoc false
  defstruct [:name, :source_hint, :payload, :handled, :message]
end

defmodule Beamwarden.Tools do
  @moduledoc false

  alias Beamwarden.{PortingBacklog, PortingModule, ToolExecution, ToolPermissionContext}

  @ported_tools Enum.map(Beamwarden.ReferenceData.tools_snapshot(), fn entry ->
                  %PortingModule{
                    name: entry["name"],
                    responsibility: entry["responsibility"],
                    source_hint: entry["source_hint"],
                    status: "mirrored"
                  }
                end)

  def ported_tools, do: @ported_tools
  def tool_names, do: Enum.map(@ported_tools, & &1.name)

  def build_tool_backlog do
    %PortingBacklog{title: "Tool surface", modules: @ported_tools}
  end

  def get_tool(name) do
    Enum.find(@ported_tools, &(String.downcase(&1.name) == String.downcase(name)))
  end

  def filter_tools_by_permission_context(tools, nil), do: tools

  def filter_tools_by_permission_context(tools, %ToolPermissionContext{} = context) do
    Enum.reject(tools, &ToolPermissionContext.blocks_module?(context, &1))
  end

  def get_tools(opts \\ []) do
    simple_mode = Keyword.get(opts, :simple_mode, false)
    include_mcp = Keyword.get(opts, :include_mcp, true)
    permission_context = Keyword.get(opts, :permission_context)

    @ported_tools
    |> maybe_filter(simple_mode, fn module ->
      module.name in ["BashTool", "FileReadTool", "FileEditTool"]
    end)
    |> maybe_reject(fn module ->
      not include_mcp and
        (String.contains?(String.downcase(module.name), "mcp") or
           String.contains?(String.downcase(module.source_hint), "mcp"))
    end)
    |> filter_tools_by_permission_context(permission_context)
  end

  def find_tools(query, limit \\ 20) do
    needle = String.downcase(query)

    @ported_tools
    |> Enum.filter(fn module ->
      String.contains?(String.downcase(module.name), needle) or
        String.contains?(String.downcase(module.source_hint), needle)
    end)
    |> Enum.take(limit)
  end

  def execute_tool(name, payload \\ "") do
    case get_tool(name) do
      nil ->
        %ToolExecution{
          name: name,
          source_hint: "",
          payload: payload,
          handled: false,
          message: "Unknown mirrored tool: #{name}"
        }

      module ->
        %ToolExecution{
          name: module.name,
          source_hint: module.source_hint,
          payload: payload,
          handled: true,
          message:
            "Mirrored tool '#{module.name}' from #{module.source_hint} would handle payload #{inspect(payload)}."
        }
    end
  end

  def render_tool_index(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    query = Keyword.get(opts, :query)

    modules =
      opts
      |> get_tools()
      |> then(fn modules ->
        if query do
          needle = String.downcase(query)

          Enum.filter(modules, fn module ->
            String.contains?(String.downcase(module.name), needle) or
              String.contains?(String.downcase(module.source_hint), needle)
          end)
        else
          modules
        end
      end)
      |> Enum.take(limit)

    [
      "Tool entries: #{length(@ported_tools)}",
      "",
      if(query, do: "Filtered by: #{query}", else: nil),
      if(query, do: "", else: nil),
      Enum.map(modules, &"- #{&1.name} — #{&1.source_hint}")
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp maybe_filter(modules, true, predicate), do: Enum.filter(modules, predicate)
  defp maybe_filter(modules, false, _predicate), do: modules
  defp maybe_reject(modules, predicate), do: Enum.reject(modules, predicate)
end
