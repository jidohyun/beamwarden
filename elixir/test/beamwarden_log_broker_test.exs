defmodule BeamwardenLogBrokerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "event store assigns monotonic event_seq values per run" do
    run_id = unique_id("phase4-event-seq")
    on_exit(fn -> File.rm(Beamwarden.event_path(run_id)) end)

    first = Beamwarden.EventStore.append(run_id, %{type: "run_started"})
    second = Beamwarden.EventStore.append(run_id, %{type: "task_created"})

    assert event_seq(first) == 1
    assert event_seq(second) == 2

    assert {:ok, events} = Beamwarden.EventStore.list(run_id)
    assert Enum.map(events, &event_seq/1) == [1, 2]
  end

  test "logs --follow hands off from replay to live delivery without duplicate cursors" do
    run_id = unique_id("phase4-follow")
    parent = self()
    worker_id = "#{run_id}-worker-1"

    on_exit(fn ->
      release_signal(worker_id, :release_phase4_follow_worker)
      stop_run_if_running(run_id)
      cleanup_run_artifacts(run_id)
    end)

    executor = fn task ->
      send(parent, {:phase4_follow_worker_started, task.task_id, task.attempt})

      receive do
        :release_phase4_follow_worker -> {:ok, "follow complete"}
      after
        1_500 -> {:error, "timed out waiting for phase4 follow release"}
      end
    end

    assert {:ok, snapshot} =
             Beamwarden.Orchestrator.start_run("review this repo",
               run_id: run_id,
               workers: 1,
               await_timeout: 50,
               worker_opts: [executor: executor]
             )

    [task] = snapshot.tasks
    task_id = task.task_id
    assert_receive {:phase4_follow_worker_started, ^task_id, 1}, 1_000

    follower =
      Task.async(fn ->
        capture_io(fn ->
          assert 0 ==
                   Beamwarden.CLI.main([
                     "logs",
                     run_id,
                     "--follow",
                     "--follow-interval-ms",
                     "25",
                     "--follow-timeout-ms",
                     "1500"
                   ])
        end)
      end)

    Process.sleep(100)
    release_signal(worker_id, :release_phase4_follow_worker)

    output = Task.await(follower, 2_000)
    event_seqs = extract_event_seqs(output)

    assert output =~ "Run Logs"
    assert output =~ "follow_supported=true"
    assert output =~ "source=replay"
    assert output =~ "source=live"
    assert output =~ "follow=live"
    assert output =~ "task_assigned"
    assert output =~ "task_completed"
    assert output =~ "follow=complete status=completed"
    assert length(event_seqs) >= 2
    assert event_seqs == Enum.sort(event_seqs)
    assert length(event_seqs) == length(Enum.uniq(event_seqs))
  end

  defp extract_event_seqs(output) do
    Regex.scan(~r/event_seq=(\d+)/, output, capture: :all_but_first)
    |> Enum.map(fn [seq] -> String.to_integer(seq) end)
  end

  defp event_seq(event), do: value(event, :event_seq)

  defp value(nil, _key), do: nil

  defp value(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> nil
    end
  end

  defp release_signal(worker_id, message) do
    case Beamwarden.WorkerSupervisor.worker_pid(worker_id) do
      {:ok, pid} -> send(pid, message)
      :error -> :ok
    end
  end

  defp stop_run_if_running(run_id) do
    case Registry.lookup(Beamwarden.RunRegistry, run_id) do
      [{pid, _value} | _] -> GenServer.stop(pid, :normal, 1_000)
      [] -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  defp cleanup_run_artifacts(run_id) do
    File.rm(Beamwarden.run_path(run_id))
    File.rm(Beamwarden.event_path(run_id))

    Beamwarden.WorkerStore.list(run_id: run_id)
    |> Enum.each(fn snapshot ->
      File.rm(Beamwarden.worker_path(snapshot["worker_id"] || snapshot[:worker_id]))
    end)
  end

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
