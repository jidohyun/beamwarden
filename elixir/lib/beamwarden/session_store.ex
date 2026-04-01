defmodule Beamwarden.StoredSession do
  @moduledoc false
  defstruct [:session_id, :messages, :input_tokens, :output_tokens, :owner_node]
end

defmodule Beamwarden.SessionStore do
  @moduledoc false

  alias Beamwarden.StoredSession

  def save_session(%StoredSession{} = session, directory \\ Beamwarden.session_root()) do
    File.mkdir_p!(directory)
    path = Path.join(directory, "#{session.session_id}.json")

    payload = %{
      session_id: session.session_id,
      messages: session.messages,
      input_tokens: session.input_tokens,
      output_tokens: session.output_tokens,
      owner_node: session.owner_node || current_owner_node()
    }

    File.write!(path, JSON.encode!(payload))
    path
  end

  def load_session(session_id, directory \\ Beamwarden.session_root()) do
    path = Path.join(directory, "#{session_id}.json")
    data = path |> File.read!() |> JSON.decode!()

    %StoredSession{
      session_id: data["session_id"],
      messages: data["messages"],
      input_tokens: data["input_tokens"],
      output_tokens: data["output_tokens"],
      owner_node: data["owner_node"]
    }
  end

  def owner_node(session_id, directory \\ Beamwarden.session_root()) do
    path = Path.join(directory, "#{session_id}.json")

    case File.read(path) do
      {:ok, contents} ->
        contents
        |> JSON.decode!()
        |> Map.get("owner_node")

      {:error, :enoent} ->
        nil
    end
  end

  defp current_owner_node do
    if Node.alive?(), do: Atom.to_string(node()), else: nil
  end
end
