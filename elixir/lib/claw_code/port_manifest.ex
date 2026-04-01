defmodule ClawCode.PortManifest do
  @moduledoc false

  alias ClawCode.Subsystem

  defstruct src_root: nil, total_elixir_files: nil, top_level_modules: []

  @notes %{
    "application.ex" => "OTP application bootstrap",
    "bootstrap_graph.ex" => "bootstrap/runtime graph stages",
    "command_graph.ex" => "command segmentation metadata",
    "commands.ex" => "command backlog metadata",
    "context.ex" => "workspace context counting",
    "deferred_init.ex" => "trust-gated deferred init summary",
    "direct_modes.ex" => "direct/deep-link mode placeholders",
    "execution_registry.ex" => "mirrored command/tool execution registry",
    "history.ex" => "session history log",
    "main.ex" => "CLI dispatcher",
    "models.ex" => "shared structs",
    "parity_audit.ex" => "archive parity inventory audit",
    "permissions.ex" => "deny-name / deny-prefix filtering",
    "port_manifest.ex" => "workspace manifest generation",
    "prefetch.ex" => "simulated bootstrap prefetch hooks",
    "query_engine.ex" => "session and turn-loop skeleton",
    "reference_data.ex" => "snapshot-backed inventory loader",
    "remote_runtime.ex" => "remote / ssh / teleport placeholders",
    "runtime.ex" => "routing/bootstrap orchestration",
    "session_store.ex" => "persisted session storage",
    "setup.ex" => "startup report builder",
    "system_init.ex" => "system init summary",
    "tool_pool.ex" => "assembled tool pool summary",
    "tools.ex" => "tool backlog metadata",
    "transcript.ex" => "transcript replay/flush state"
  }

  def build(root \\ ClawCode.source_root()) do
    files = root |> Path.join("**/*.ex") |> Path.wildcard() |> Enum.sort()

    frequencies =
      Enum.frequencies_by(files, fn path ->
        path
        |> Path.relative_to(root)
        |> String.split("/", trim: true)
        |> case do
          [name] -> name
          [dir | _rest] -> dir
        end
      end)

    top_level_modules =
      frequencies
      |> Enum.map(fn {name, count} ->
        %Subsystem{
          name: name,
          path: Path.join("lib/claw_code", name),
          file_count: count,
          notes: Map.get(@notes, name, "Elixir port support module")
        }
      end)
      |> Enum.sort_by(fn subsystem -> {-subsystem.file_count, subsystem.name} end)

    %__MODULE__{
      src_root: root,
      total_elixir_files: length(files),
      top_level_modules: top_level_modules
    }
  end

  def to_markdown(%__MODULE__{} = manifest) do
    lines = [
      "Port root: `#{manifest.src_root}`",
      "Total Elixir files: **#{manifest.total_elixir_files}**",
      "",
      "Top-level Elixir modules:"
    ]

    Enum.join(
      lines ++
        Enum.map(
          manifest.top_level_modules,
          &"- `#{&1.name}` (#{&1.file_count} files) — #{&1.notes}"
        ),
      "\n"
    )
  end
end
