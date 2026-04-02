defmodule Beamwarden.ReplLauncher do
  @moduledoc false

  def launch_message do
    "Elixir porting REPL is not interactive yet; use `mix beamwarden summary` instead."
  end

  def build_banner do
    "Elixir porting REPL is workflow-oriented; prefer `mix beamwarden summary` or the control-plane commands."
  end
end
