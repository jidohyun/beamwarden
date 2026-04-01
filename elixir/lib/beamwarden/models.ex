defmodule Beamwarden.Subsystem do
  @moduledoc false
  defstruct [:name, :path, :file_count, :notes]
end

defmodule Beamwarden.PortingModule do
  @moduledoc false
  defstruct name: nil, responsibility: nil, source_hint: nil, status: "planned"
end

defmodule Beamwarden.PermissionDenial do
  @moduledoc false
  defstruct [:tool_name, :reason]
end

defmodule Beamwarden.UsageSummary do
  @moduledoc false
  defstruct input_tokens: 0, output_tokens: 0

  def add_turn(%__MODULE__{} = usage, prompt, output) do
    %__MODULE__{
      input_tokens: usage.input_tokens + token_count(prompt),
      output_tokens: usage.output_tokens + token_count(output)
    }
  end

  defp token_count(text) do
    text
    |> to_string()
    |> String.split()
    |> length()
  end
end

defmodule Beamwarden.PortingBacklog do
  @moduledoc false
  defstruct title: nil, modules: []

  def summary_lines(%__MODULE__{modules: modules}) do
    Enum.map(
      modules,
      &"- #{&1.name} [#{&1.status}] — #{&1.responsibility} (from #{&1.source_hint})"
    )
  end
end
