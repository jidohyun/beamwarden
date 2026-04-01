defmodule Beamwarden.Query do
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

defmodule Beamwarden.QueryRequest do
  @moduledoc false
  defstruct [:prompt]
end

defmodule Beamwarden.QueryResponse do
  @moduledoc false
  defstruct [:text, :session_id, :stop_reason, matched_commands: [], matched_tools: []]
end
