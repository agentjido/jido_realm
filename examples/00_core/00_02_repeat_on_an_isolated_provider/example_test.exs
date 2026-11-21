Code.require_file("../00_01_work_on_one_tree/example.ex", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.ProfiledReportTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Realm.Host.Examples.ProfiledReport

  setup do
    previous = Application.fetch_env(:jido_realm, :profiles)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_realm, :profiles, value)
        :error -> Application.delete_env(:jido_realm, :profiles)
      end
    end)

    Application.put_env(:jido_realm, :profiles, %{
      memory: %{provider: :memory, policy: :full_access},
      docker: %{
        provider: :docker,
        policy: :full_access,
        image: System.get_env("JIDO_SANDBOX_IMAGE", "alpine:latest"),
        require: %{isolation: :container, network: :disabled}
      }
    })
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to repeat the memory workflow on Docker"
  end

  test "memory and Docker run the same Workspace workflow" do
    input = "Report for today\n"

    assert {:ok, ^input} = ProfiledReport.run(:memory, input)
    assert {:ok, ^input} = ProfiledReport.run(:docker, input)
  end
end
