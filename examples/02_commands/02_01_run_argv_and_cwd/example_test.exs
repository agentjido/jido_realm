Code.require_file("../../05_lifecycle/support.exs", __DIR__)
Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.ReadReportsTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Realm.Host
  alias Jido.Realm.Host.{Error, Execution}
  alias Jido.Realm.Host.Examples.ReadReports
  import Jido.Realm.Host.Examples.LifecycleSupport, only: [configure: 1]

  @directory "monthly reports"
  @literal_name "draft $(echo changed).txt"
  @report "Approved report\n"

  setup %{tmp_dir: root}, do: configure(root)

  test "memory returns a nonzero result with partial output and resolves literal names in cwd" do
    check_report_reads(:memory)
  end

  if System.get_env("JIDO_SANDBOX_DOCKER") != "1" do
    @tag skip: "Set JIDO_SANDBOX_DOCKER=1 to test the same command on Docker"
  end

  test "Docker returns a nonzero result with partial output and resolves literal names in cwd" do
    check_report_reads(:docker)
  end

  defp check_report_reads(profile) do
    assert {:ok, workspace} = Host.open(profile: profile)

    try do
      assert :ok = Host.mkdir(workspace, @directory)
      assert :ok = Host.write(workspace, @literal_name, "Draft from the root")
      assert :ok = Host.write(workspace, Path.join(@directory, @literal_name), @report)

      assert {:ok,
              %Execution{
                command: ["cat", @literal_name],
                status: :exited,
                exit_status: 0,
                output: @report,
                truncated: false
              }} = ReadReports.read(workspace, @directory, [@literal_name], 1_024)

      names = [@literal_name, "missing.txt"]

      assert {:incomplete,
              %Execution{status: :exited, exit_status: 1, output: output, truncated: false}} =
               ReadReports.read(workspace, @directory, names, 1_024)

      assert String.contains?(output, @report)
      assert String.contains?(output, "missing.txt")

      assert {:incomplete,
              %Execution{status: :exited, exit_status: 1, output: bounded, truncated: true}} =
               ReadReports.read(workspace, @directory, names, 8)

      assert byte_size(bounded) == 8

      assert {:ok,
              %Execution{status: :exited, exit_status: 0, output: "Approved", truncated: true}} =
               ReadReports.read(workspace, @directory, [@literal_name], 8)

      assert {:error, %Error{code: :not_found, operation: :run}} =
               ReadReports.read(workspace, "missing directory", [@literal_name], 8)

      assert {:error, %Error{code: :not_directory, operation: :run}} =
               ReadReports.read(workspace, @literal_name, [@literal_name], 8)

      assert {:ok, %{phase: :ready}} = Host.info(workspace)
      assert {:ok, %{kind: "snapshot"}} = Host.save(workspace)
    after
      assert :ok = Host.close(workspace)
    end
  end
end
