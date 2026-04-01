defmodule Beamwarden.PortManifest do
  @moduledoc false

  alias Beamwarden.Subsystem

  defstruct src_root: nil, total_elixir_files: nil, top_level_modules: []

  @notes %{
    "application.ex" => "OTP application bootstrap",
    "bootstrap_graph.ex" => "bootstrap/runtime graph stages",
    "command_graph.ex" => "command segmentation metadata",
    "commands.ex" => "command backlog metadata",
    "control_plane.ex" => "OTP-native session/workflow orchestration",
    "context.ex" => "workspace context counting",
    "cost_hook.ex" => "cost hook/report helpers",
    "cost_tracker.ex" => "usage/cost tracking helpers",
    "deferred_init.ex" => "trust-gated deferred init summary",
    "dialog_launchers.ex" => "dialog launcher placeholders",
    "direct_modes.ex" => "direct/deep-link mode placeholders",
    "execution_registry.ex" => "mirrored command/tool execution registry",
    "history.ex" => "session history log",
    "ink.ex" => "terminal rendering helpers",
    "interactive_helpers.ex" => "interactive prompt helpers",
    "main.ex" => "CLI dispatcher",
    "models.ex" => "shared structs",
    "parity_audit.ex" => "archive parity inventory audit",
    "permissions.ex" => "deny-name / deny-prefix filtering",
    "port_manifest.ex" => "workspace manifest generation",
    "prefetch.ex" => "simulated bootstrap prefetch hooks",
    "project_onboarding_state.ex" => "project onboarding state helpers",
    "query.ex" => "query request helpers",
    "query_engine.ex" => "session and turn-loop skeleton",
    "reference_data.ex" => "snapshot-backed inventory loader",
    "remote_runtime.ex" => "remote / ssh / teleport placeholders",
    "repl_launcher.ex" => "REPL launcher placeholder",
    "runtime.ex" => "routing/bootstrap orchestration",
    "session_store.ex" => "persisted session storage",
    "session_server.ex" => "supervised session runtime",
    "setup.ex" => "startup report builder",
    "system_init.ex" => "system init summary",
    "task.ex" => "workflow task structs",
    "tasks.ex" => "workflow task helpers",
    "tool.ex" => "tool request/result helpers",
    "tool_pool.ex" => "assembled tool pool summary",
    "tool_definition.ex" => "lightweight tool definition companions",
    "tools.ex" => "tool backlog metadata",
    "transcript.ex" => "transcript replay/flush state",
    "workflow_server.ex" => "supervised workflow runtime"
  }

  def build(root \\ Beamwarden.source_root()) do
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
          path: Path.join("lib/beamwarden", name),
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
