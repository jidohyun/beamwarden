defmodule Beamwarden.ParityAuditResult do
  @moduledoc false

  defstruct [
    :archive_present,
    :root_file_coverage,
    :directory_coverage,
    :total_file_ratio,
    :command_entry_ratio,
    :tool_entry_ratio,
    :missing_root_targets,
    :missing_directory_targets
  ]

  def to_markdown(%__MODULE__{archive_present: false}) do
    Enum.join(
      [
        "# Parity Audit",
        "Local archive unavailable; parity audit cannot compare against the original snapshot."
      ],
      "\n"
    )
  end

  def to_markdown(%__MODULE__{} = result) do
    [
      "# Parity Audit",
      "",
      "Root file coverage: **#{elem(result.root_file_coverage, 0)}/#{elem(result.root_file_coverage, 1)}**",
      "Directory coverage: **#{elem(result.directory_coverage, 0)}/#{elem(result.directory_coverage, 1)}**",
      "Total Elixir files vs archived TS-like files: **#{elem(result.total_file_ratio, 0)}/#{elem(result.total_file_ratio, 1)}**",
      "Command entry coverage: **#{elem(result.command_entry_ratio, 0)}/#{elem(result.command_entry_ratio, 1)}**",
      "Tool entry coverage: **#{elem(result.tool_entry_ratio, 0)}/#{elem(result.tool_entry_ratio, 1)}**",
      "",
      "Missing root targets:",
      if(result.missing_root_targets == [],
        do: ["- none"],
        else: Enum.map(result.missing_root_targets, &"- #{&1}")
      ),
      "",
      "Missing directory targets:",
      if(result.missing_directory_targets == [],
        do: ["- none"],
        else: Enum.map(result.missing_directory_targets, &"- #{&1}")
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end

defmodule Beamwarden.ParityAudit do
  @moduledoc false

  alias Beamwarden.ParityAuditResult

  @archive_root_files [
    "main.ex",
    "query_engine.ex",
    "commands.ex",
    "tools.ex",
    "context.ex",
    "port_manifest.ex",
    "parity_audit.ex",
    "runtime.ex",
    "setup.ex",
    "permissions.ex",
    "session_store.ex",
    "transcript.ex",
    "history.ex"
  ]

  @archive_dir_targets [
    "bootstrap_graph.ex",
    "command_graph.ex",
    "direct_modes.ex",
    "execution_registry.ex",
    "prefetch.ex",
    "deferred_init.ex",
    "remote_runtime.ex",
    "system_init.ex",
    "tool_pool.ex"
  ]

  def run do
    current_entries =
      Beamwarden.source_root()
      |> File.ls!()
      |> Enum.reject(&String.starts_with?(&1, "."))

    root_hits = Enum.filter(@archive_root_files, &(&1 in current_entries))
    dir_hits = Enum.filter(@archive_dir_targets, &(&1 in current_entries))
    reference = Beamwarden.ReferenceData.archive_surface_snapshot()
    current_elixir_files = count_source_files()

    %ParityAuditResult{
      archive_present: File.dir?(Beamwarden.archive_root()),
      root_file_coverage: {length(root_hits), length(@archive_root_files)},
      directory_coverage: {length(dir_hits), length(@archive_dir_targets)},
      total_file_ratio: {current_elixir_files, reference["total_ts_like_files"]},
      command_entry_ratio:
        {length(Beamwarden.ReferenceData.commands_snapshot()), reference["command_entry_count"]},
      tool_entry_ratio:
        {length(Beamwarden.ReferenceData.tools_snapshot()), reference["tool_entry_count"]},
      missing_root_targets: @archive_root_files -- root_hits,
      missing_directory_targets: @archive_dir_targets -- dir_hits
    }
  end

  defp count_source_files do
    Beamwarden.source_root()
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.count()
  end
end
