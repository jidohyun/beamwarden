defmodule Beamwarden.AppIdentity do
  @moduledoc false

  @runtime_app :beamwarden

  def runtime_app, do: @runtime_app

  def ensure_started do
    ensure_runtime_started()
  end

  def ensure_runtime_started do
    case Application.ensure_all_started(runtime_app()) do
      {:ok, _apps} -> :ok
      other -> other
    end
  end

  def get_env(key, default \\ nil) do
    Application.get_env(runtime_app(), key, default)
  end

  def put_env(key, value) do
    Application.put_env(runtime_app(), key, value)
  end

  def delete_env(key) do
    Application.delete_env(runtime_app(), key)
    :ok
  end
end
