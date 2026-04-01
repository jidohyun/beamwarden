defmodule Mix.Tasks.Claw do
  use Mix.Task

  @shortdoc "Run the Elixir structural mirror CLI"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    case ClawCode.Main.run(args) do
      {:ok, output} ->
        IO.puts(output)

      {:error, output} ->
        IO.puts(output)
        System.halt(1)
    end
  end
end
