defmodule Jido.Realm.Integration.StreamTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture}

  defp interrupt(:read_stream, "interrupted", _, run) do
    {:ok, chunks} = run.()
    {:ok, Stream.concat(Stream.take(chunks, 1), [{:error, :transfer_interrupted}])}
  end

  defp interrupt(_, _, _, run), do: run.()

  defp observe_buffer(owner) do
    fn operation, _, _input, run ->
      if operation == :read_stream do
        {:ok, chunks} = run.()

        {:ok,
         Stream.map(chunks, fn chunk ->
           if is_binary(chunk), do: send(owner, {:observed_chunk, byte_size(chunk)})
           chunk
         end)}
      else
        run.()
      end
    end
  end

  defp source_hook(owner) do
    fn
      :read_stream, "interrupted", input, run ->
        interrupt(:read_stream, "interrupted", input, run)

      op, path, input, run ->
        observe_buffer(owner).(op, path, input, run)
    end
  end

  defp report_source_worker(observer) do
    fn :read_stream, _path, _input, run ->
      send(observer, {:source_worker, self()})
      run.()
    end
  end

  defp hold_destination_reply(observer) do
    fn :write_stream, path, _input, run ->
      :ok = run.()
      send(observer, {:stream_published, path, self()})

      receive do
        :finish_reply -> :ok
      after
        3_000 -> {:error, :unknown}
      end
    end
  end

  realm_case "01.05 stream binary files and publish only complete results",
    agent: AgentJobs.Pair,
    cases: [
      local_to_memory: [
        source: {BindingFixture, kind: :local, hook: source_hook(self())},
        target: {BindingFixture, kind: :memory}
      ],
      memory_to_local: [
        source: {BindingFixture, kind: :memory, hook: source_hook(self())},
        target: {BindingFixture, kind: :local}
      ]
    ] do
    %{agent: agent, placements: %{source: source, target: target}} ->
      assert :streams in AgentJobs.succeeded(agent, :open, %{realm: :source}).capabilities
      assert :streams in AgentJobs.succeeded(agent, :open, %{realm: :target}).capabilities

      bytes = :binary.copy(<<0, 255, 17, 128>>, 1_024)
      source.seed.("payload", bytes)
      source.seed.("interrupted", bytes)
      target.seed.("previous", "last complete result")

      AgentJobs.succeeded(agent, :stream, %{path: "payload", to: "complete"})
      assert {:ok, copied} = target.observe.("complete")
      assert :crypto.hash(:sha256, bytes) == :crypto.hash(:sha256, copied)

      for _ <- 1..div(byte_size(bytes), 64) do
        assert_receive {:observed_chunk, 64}
      end

      refute_received {:observed_chunk, _}

      AgentJobs.rejected(agent, :stream, :transfer_interrupted, %{
        path: "interrupted",
        to: "previous",
        replace: true
      })

      assert target.observe.("previous") == {:ok, "last complete result"}

      AgentJobs.rejected(agent, :stream, :transfer_interrupted, %{
        path: "interrupted",
        to: "missing"
      })

      assert target.observe.("missing") == {:error, :not_found}

      AgentJobs.succeeded(agent, :close, %{realm: :source})
      AgentJobs.succeeded(agent, :close, %{realm: :target})
  end

  realm_case "01.05 report an unknown result if shutdown loses a published transfer reply",
    agent: AgentJobs.Pair,
    cases: [
      local_to_memory: [
        source: {BindingFixture, kind: :local, hook: report_source_worker(self())},
        target: {BindingFixture, kind: :memory, hook: hold_destination_reply(self())}
      ]
    ] do
    %{agent: agent, bindings: bindings, placements: %{source: source, target: target}} ->
      AgentJobs.succeeded(agent, :open, %{realm: :source})
      AgentJobs.succeeded(agent, :open, %{realm: :target})
      bytes = <<0, 255, 17, 128>>
      source.seed.("payload", bytes)

      transfer =
        Task.async(fn ->
          AgentJobs.rejected(agent, :stream, :unknown, %{path: "payload", to: "published"})
        end)

      assert_receive {:source_worker, source_worker}, 1_000
      assert_receive {:stream_published, "published", target_worker}, 1_000
      assert target.observe.("published") == {:ok, bytes}
      source_monitor = Process.monitor(source_worker)
      source_session = Keyword.fetch!(bindings.source, :session)
      :ok = GenServer.stop(source_session)

      assert_receive {:DOWN, ^source_monitor, :process, ^source_worker, :killed}
      Task.await(transfer)
      refute_received {:placement_released, :source, _}
      send(target_worker, :finish_reply)

      AgentJobs.rejected(agent, :open, :session_closed, %{realm: :source})
      assert source.observe.("payload") == {:ok, bytes}
      assert target.observe.("published") == {:ok, bytes}
      refute_received {:stream_published, _, _}
  end
end
