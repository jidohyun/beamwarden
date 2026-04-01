defmodule Beamwarden.WorkspaceSetup do
  @moduledoc false
  defstruct [:elixir_version, :otp_release, :test_command, :format_command, :compile_command]

  def startup_steps do
    [
      "start top-level prefetch side effects",
      "build workspace context",
      "load mirrored command snapshot",
      "load mirrored tool snapshot",
      "prepare parity audit hooks",
      "apply trust-gated deferred init"
    ]
  end
end

defmodule Beamwarden.SetupReport do
  @moduledoc false
  defstruct [:setup, :prefetches, :deferred_init, :trusted, :cwd]

  def as_markdown(%__MODULE__{} = report) do
    [
      "# Setup Report",
      "",
      "- Elixir: #{report.setup.elixir_version}",
      "- OTP: #{report.setup.otp_release}",
      "- Trusted mode: #{report.trusted}",
      "- CWD: #{report.cwd}",
      "",
      "Prefetches:",
      Enum.map(report.prefetches, &"- #{&1.name}: #{&1.detail}"),
      "",
      "Deferred init:",
      Beamwarden.DeferredInitResult.as_lines(report.deferred_init)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end

defmodule Beamwarden.Setup do
  @moduledoc false

  alias Beamwarden.{DeferredInit, Prefetch, SetupReport, WorkspaceSetup}

  def build_workspace_setup do
    %WorkspaceSetup{
      elixir_version: System.version(),
      otp_release: System.otp_release(),
      test_command: "cd elixir && mix test",
      format_command: "cd elixir && mix format --check-formatted",
      compile_command: "cd elixir && mix compile"
    }
  end

  def run(cwd \\ Beamwarden.repo_root(), trusted \\ true) do
    %SetupReport{
      setup: build_workspace_setup(),
      prefetches: [
        Prefetch.start_mdm_raw_read(),
        Prefetch.start_keychain_prefetch(),
        Prefetch.start_project_scan(cwd)
      ],
      deferred_init: DeferredInit.run(trusted),
      trusted: trusted,
      cwd: cwd
    }
  end
end
