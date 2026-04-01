defmodule ClawCode do
  @moduledoc false

  def project_root do
    Path.expand("..", __DIR__)
  end

  def repo_root do
    Path.expand("..", project_root())
  end

  def source_root do
    Path.join(project_root(), "lib/claw_code")
  end

  def test_root do
    Path.join(project_root(), "test")
  end

  def assets_root do
    Path.join(repo_root(), "assets")
  end

  def archive_root do
    Path.join(repo_root(), "archive/claude_code_ts_snapshot/src")
  end

  def reference_data_root do
    Path.join(repo_root(), "src/reference_data")
  end

  def subsystem_snapshot_root do
    Path.join(reference_data_root(), "subsystems")
  end

  def session_root do
    Path.join(project_root(), ".port_sessions")
  end
end
