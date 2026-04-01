defmodule ClawCode.Query do
  @moduledoc false

  defstruct prompt: nil,
            matched_commands: [],
            matched_tools: [],
            denied_tools: [],
            metadata: %{}

  def from_prompt(prompt, opts \\ []) do
    %__MODULE__{
      prompt: prompt,
      matched_commands: Keyword.get(opts, :matched_commands, []),
      matched_tools: Keyword.get(opts, :matched_tools, []),
      denied_tools: Keyword.get(opts, :denied_tools, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
