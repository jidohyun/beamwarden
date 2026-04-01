defmodule ClawCode.StoredSession do
  @moduledoc false
  defstruct [:session_id, :messages, :input_tokens, :output_tokens]
end

defmodule ClawCode.SessionStore do
  @moduledoc false

  alias ClawCode.StoredSession

  def save_session(%StoredSession{} = session, directory \\ ClawCode.session_root()) do
    File.mkdir_p!(directory)
    path = Path.join(directory, "#{session.session_id}.json")

    payload = %{
      session_id: session.session_id,
      messages: session.messages,
      input_tokens: session.input_tokens,
      output_tokens: session.output_tokens
    }

    File.write!(path, JSON.encode!(payload))
    path
  end

  def load_session(session_id, directory \\ ClawCode.session_root()) do
    path = Path.join(directory, "#{session_id}.json")
    data = path |> File.read!() |> JSON.decode!()

    %StoredSession{
      session_id: data["session_id"],
      messages: data["messages"],
      input_tokens: data["input_tokens"],
      output_tokens: data["output_tokens"]
    }
  end
end
