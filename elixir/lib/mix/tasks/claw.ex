defmodule Mix.Tasks.Claw do
  use Mix.Task

  @shortdoc "Run the Elixir structural mirror CLI"

  @impl true
  def run(args) do
    args
    |> ClawCode.Main.run()
    |> IO.puts()
  end
end
