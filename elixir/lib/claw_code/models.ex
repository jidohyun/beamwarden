defmodule ClawCode.Subsystem do
  @moduledoc false
  defstruct [:name, :path, :file_count, :notes]
end

defmodule ClawCode.PortingModule do
  @moduledoc false
  defstruct [:name, :responsibility, :source_hint, status: "planned"]
end

defmodule ClawCode.PermissionDenial do
  @moduledoc false
  defstruct [:tool_name, :reason]
end

defmodule ClawCode.UsageSummary do
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

defmodule ClawCode.PortingBacklog do
  @moduledoc false
  defstruct title: nil, modules: []

  def summary_lines(%__MODULE__{modules: modules}) do
    Enum.map(
      modules,
      &"- #{&1.name} [#{&1.status}] — #{&1.responsibility} (from #{&1.source_hint})"
    )
  end
end
