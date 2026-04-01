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
    Path.join(project_root(), "priv/reference_data")
  end

  def subsystem_snapshot_root do
    Path.join(reference_data_root(), "subsystems")
  end

  def session_root do
    Path.join(project_root(), ".port_sessions")
  end

  def workflow_root do
    Path.join(session_root(), "workflows")
  end

  def cluster_root do
    Path.join(session_root(), "cluster")
  end

  def cluster_node_root do
    node_label =
      if Node.alive?(), do: Atom.to_string(node()), else: "local"

    sanitized =
      node_label
      |> String.replace(~r/[^a-zA-Z0-9._-]/u, "_")

    Path.join(cluster_root(), sanitized)
  end

  def cluster_ledger_path do
    Path.join(cluster_node_root(), "ledger.dets")
  end

  def session_path(session_id) do
    Path.join(session_root(), "#{session_id}.json")
  end

  def workflow_path(workflow_id) do
    Path.join(workflow_root(), "#{workflow_id}.json")
  end
end
