defmodule ClawCode.CommandExecution do
  @moduledoc false
  defstruct [:name, :source_hint, :prompt, :handled, :message]
end

defmodule ClawCode.Commands do
  @moduledoc false

  alias ClawCode.{CommandExecution, PortingBacklog, PortingModule}

  @ported_commands Enum.map(ClawCode.ReferenceData.commands_snapshot(), fn entry ->
                     %PortingModule{
                       name: entry["name"],
                       responsibility: entry["responsibility"],
                       source_hint: entry["source_hint"],
                       status: "mirrored"
                     }
                   end)

  def ported_commands, do: @ported_commands
  def built_in_command_names, do: @ported_commands |> Enum.map(& &1.name) |> MapSet.new()
  def command_names, do: Enum.map(@ported_commands, & &1.name)

  def build_command_backlog do
    %PortingBacklog{title: "Command surface", modules: @ported_commands}
  end

  def get_command(name) do
    Enum.find(@ported_commands, &(String.downcase(&1.name) == String.downcase(name)))
  end

  def get_commands(opts \\ []) do
    include_plugin_commands = Keyword.get(opts, :include_plugin_commands, true)
    include_skill_commands = Keyword.get(opts, :include_skill_commands, true)

    @ported_commands
    |> maybe_reject(fn module ->
      not include_plugin_commands and String.contains?(String.downcase(module.source_hint), "plugin")
    end)
    |> maybe_reject(fn module ->
      not include_skill_commands and String.contains?(String.downcase(module.source_hint), "skills")
    end)
  end

  def find_commands(query, limit \\ 20) do
    needle = String.downcase(query)

    @ported_commands
    |> Enum.filter(fn module ->
      String.contains?(String.downcase(module.name), needle) or
        String.contains?(String.downcase(module.source_hint), needle)
    end)
    |> Enum.take(limit)
  end

  def execute_command(name, prompt \\ "") do
    case get_command(name) do
      nil ->
        %CommandExecution{
          name: name,
          source_hint: "",
          prompt: prompt,
          handled: false,
          message: "Unknown mirrored command: #{name}"
        }

      module ->
        %CommandExecution{
          name: module.name,
          source_hint: module.source_hint,
          prompt: prompt,
          handled: true,
          message:
            "Mirrored command '#{module.name}' from #{module.source_hint} would handle prompt #{inspect(prompt)}."
        }
    end
  end

  def render_command_index(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    query = Keyword.get(opts, :query)
    modules = if query, do: find_commands(query, limit), else: Enum.take(@ported_commands, limit)

    [
      "Command entries: #{length(@ported_commands)}",
      "",
      if(query, do: "Filtered by: #{query}", else: nil),
      if(query, do: "", else: nil),
      Enum.map(modules, &"- #{&1.name} — #{&1.source_hint}")
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp maybe_reject(modules, predicate) do
    Enum.reject(modules, predicate)
  end
end
