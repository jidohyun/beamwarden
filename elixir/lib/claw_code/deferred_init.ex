defmodule ClawCode.DeferredInitResult do
  @moduledoc false
  defstruct [:trusted, :plugin_init, :skill_init, :mcp_prefetch, :session_hooks]

  def as_lines(%__MODULE__{} = result) do
    [
      "- plugin_init=#{result.plugin_init}",
      "- skill_init=#{result.skill_init}",
      "- mcp_prefetch=#{result.mcp_prefetch}",
      "- session_hooks=#{result.session_hooks}"
    ]
  end
end

defmodule ClawCode.DeferredInit do
  @moduledoc false

  alias ClawCode.DeferredInitResult

  def run(trusted) do
    enabled = !!trusted

    %DeferredInitResult{
      trusted: trusted,
      plugin_init: enabled,
      skill_init: enabled,
      mcp_prefetch: enabled,
      session_hooks: enabled
    }
  end
end
