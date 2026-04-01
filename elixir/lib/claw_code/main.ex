defmodule ClawCode.Main do
  @moduledoc false

  def run(args) do
    case ClawCode.CLI.run(args) do
      {:ok, output} -> output
      {:error, output} -> output
    end
  end
end
