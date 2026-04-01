defmodule Mix.Tasks.Beamwarden do
  use Mix.Task

  @shortdoc "Run the Beamwarden CLI alias"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    status = ClawCode.CLI.main(args)
    if status != 0, do: System.halt(status)
  end
end
