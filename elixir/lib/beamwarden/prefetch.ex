defmodule Beamwarden.PrefetchResult do
  @moduledoc false
  defstruct [:name, :started, :detail]
end

defmodule Beamwarden.Prefetch do
  @moduledoc false

  alias Beamwarden.PrefetchResult

  def start_mdm_raw_read do
    %PrefetchResult{
      name: "mdm_raw_read",
      started: true,
      detail: "Simulated MDM raw-read prefetch for workspace bootstrap"
    }
  end

  def start_keychain_prefetch do
    %PrefetchResult{
      name: "keychain_prefetch",
      started: true,
      detail: "Simulated keychain prefetch for trusted startup path"
    }
  end

  def start_project_scan(root) do
    %PrefetchResult{name: "project_scan", started: true, detail: "Scanned project root #{root}"}
  end
end
