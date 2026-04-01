defmodule Beamwarden.BootstrapGraph do
  @moduledoc false

  defstruct stages: []

  def build do
    %__MODULE__{
      stages: [
        "top-level prefetch side effects",
        "warning handler and environment guards",
        "CLI parser and pre-action trust gate",
        "setup() + commands/agents parallel load",
        "deferred init after trust",
        "mode routing: local / remote / ssh / teleport / direct-connect / deep-link",
        "query engine submit loop"
      ]
    }
  end

  def as_markdown(%__MODULE__{stages: stages}) do
    Enum.join(["# Bootstrap Graph", ""] ++ Enum.map(stages, &"- #{&1}"), "\n")
  end
end
