defmodule ClawCode.ReplLauncher do
  @moduledoc false

  def launch_message do
    "Elixir porting REPL is not interactive yet; use `mix claw summary` instead."
  end

  def build_banner do
    "Elixir porting REPL is workflow-oriented; use `mix claw summary` or the control-plane commands instead."
  end
end
