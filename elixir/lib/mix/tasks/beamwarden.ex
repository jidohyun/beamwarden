defmodule Mix.Tasks.Beamwarden do
  use Mix.Task

  @shortdoc "Run the preferred Beamwarden CLI"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    status = Beamwarden.CLI.main(args)
    if status != 0, do: System.halt(status)
  end
end
