defmodule Jido.Realm.CodingRecoveryTest do
  use ExUnit.Case, async: true

  alias Jido.Realm.{Placement, Profile, Runner, Session}

  defmodule Observer do
    @behaviour Runner

    @impl true
    def prepare(:bash, _lease, observer), do: {:ok, observer}

    @impl true
    def controls(_), do: [:bash_command]

    @impl true
    def execute(observer, request, _) do
      send(observer, {:started, self(), request.resource_id})

      receive do
        :finish -> {:ok, Runner.result(:succeeded, 0, "confirmed")}
        :lost -> {:error, :unknown}
      after
        2_000 -> {:error, :unknown}
      end
    end

    def reconcile(observer, request) do
      send(observer, {:reconciled, request.resource_id})
      :ok
    end
  end

  setup do
    {:ok, profile} = Profile.resolve(:program)

    session =
      start_supervised!(
        {Session,
         owner: self(),
         provider: {Placement, :memory},
         profile: profile,
         runners: %{bash: {Observer, self()}},
         coding: [bash: true]}
      )

    assert {:ok, _} = Session.open(session, profile)
    %{session: session, profile: profile}
  end

  test "records a lost reply and attaches a repeated request to the same run", ctx do
    id = "stable"
    caller = spawn(fn -> run(ctx, id, "true") end)
    assert_receive {:started, worker, _resource}
    Process.exit(caller, :kill)
    assert {:ok, %{id: ^id, status: :running}} = run(ctx, id, "true")
    assert {:error, :request_conflict} = run(ctx, id, "false")

    send(worker, :finish)

    assert {:ok, %{id: ^id, status: :succeeded, output: "confirmed"} = terminal} =
             wait_for_terminal(ctx, id, 50)

    assert {:ok, ^terminal} = run(ctx, id, "true")
    refute_receive {:started, _, _}
    assert :ok = Session.close(ctx.session, ctx.profile)
  end

  test "keeps an uncertain lease until its owner confirms cleanup", ctx do
    id = "uncertain"
    caller = Task.async(fn -> run(ctx, id, "true") end)
    assert_receive {:started, worker, resource}
    send(worker, :lost)
    assert {:error, {:unknown, ^id}} = Task.await(caller)
    assert {:ok, %{status: :unknown}} = Session.run_status(ctx.session, ctx.profile, id)
    assert {:error, :session_closed} = run(ctx, "new", "true")
    assert {:error, {:unknown, ^id}} = Session.close(ctx.session, ctx.profile)
    stranger = Task.async(fn -> Session.reconcile_run(ctx.session, id) end)
    assert {:error, :permission_denied} = Task.await(stranger)
    assert {:ok, %{status: :stopped}} = Session.reconcile_run(ctx.session, id)
    assert_receive {:reconciled, ^resource}
    assert {:ok, %{status: :stopped}} = Session.run_status(ctx.session, ctx.profile, id)
    assert :ok = Session.close(ctx.session, ctx.profile)
  end

  defp run(ctx, id, command),
    do:
      Session.coding_run(ctx.session, ctx.profile, :bash, %{command: command}, id, [:read, :run])

  defp wait_for_terminal(ctx, id, attempts) do
    case Session.run_status(ctx.session, ctx.profile, id) do
      {:ok, %{status: :running}} when attempts > 0 ->
        Process.sleep(10)
        wait_for_terminal(ctx, id, attempts - 1)

      result ->
        result
    end
  end
end
