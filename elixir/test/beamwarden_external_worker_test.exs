defmodule BeamwardenExternalWorkerTest do
  use ExUnit.Case, async: false

  setup do
    original_command = Beamwarden.AppIdentity.get_env(:orchestrator_worker_command)

    on_exit(fn ->
      restore_env(:orchestrator_worker_command, original_command)
    end)

    :ok
  end

  test "external worker returns successful results to the run process" do
    worker_id = unique_id("worker-success")

    Beamwarden.AppIdentity.put_env(
      :orchestrator_worker_command,
      {"/bin/sh", ["-lc", "printf 'ok:%s\\n' \"$BW_TASK_PAYLOAD\""]}
    )

    {:ok, _pid} =
      Beamwarden.WorkerSupervisor.start_worker(
        worker_id: worker_id,
        run_id: "run-success",
        run_pid: self()
      )

    on_exit(fn -> Beamwarden.ExternalWorker.stop(worker_id) end)

    Beamwarden.ExternalWorker.run_task(worker_id, %{task_id: "1", payload: "review repo"})

    assert_receive {:worker_result, ^worker_id, "1", {:ok, "ok:review repo"}}, 1_000

    snapshot = Beamwarden.ExternalWorker.snapshot(worker_id)
    assert snapshot.state == "idle"
    assert snapshot.current_task_id == nil
    assert snapshot.last_result_summary == "ok:review repo"
    assert snapshot.last_exit_status == 0
  end

  test "external worker normalizes command failures" do
    worker_id = unique_id("worker-failure")

    Beamwarden.AppIdentity.put_env(
      :orchestrator_worker_command,
      {"/bin/sh", ["-lc", "echo worker failed >&2; exit 7"]}
    )

    {:ok, _pid} =
      Beamwarden.WorkerSupervisor.start_worker(
        worker_id: worker_id,
        run_id: "run-failure",
        run_pid: self()
      )

    on_exit(fn -> Beamwarden.ExternalWorker.stop(worker_id) end)

    Beamwarden.ExternalWorker.run_task(worker_id, %{task_id: "9", payload: "cause failure"})

    assert_receive {:worker_result, ^worker_id, "9", {:error, summary}}, 1_000
    assert summary =~ "worker failed"

    snapshot = Beamwarden.ExternalWorker.snapshot(worker_id)
    assert snapshot.state == "idle"
    assert snapshot.last_exit_status == 1
  end

  defp restore_env(key, nil), do: Beamwarden.AppIdentity.delete_env(key)
  defp restore_env(key, value), do: Beamwarden.AppIdentity.put_env(key, value)

  defp unique_id(prefix) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "#{prefix}-#{suffix}"
  end
end
