defmodule ClawCode.InteractiveHelpers do
  @moduledoc false

  def bulletize(items) when is_list(items) do
    Enum.map_join(items, "\n", &"- #{&1}")
  end

  def normalize_prompt(prompt) do
    prompt
    |> to_string()
    |> String.trim()
  end

  def repl_help do
    [
      "/help — show help",
      "/status — show session status",
      "/compact — compact local history",
      "/exit — leave the REPL placeholder"
    ]
  end
end
