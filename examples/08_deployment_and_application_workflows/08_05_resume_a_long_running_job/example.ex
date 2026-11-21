Code.require_file(
  "../../07_keep_useful_results/07_02_publish_a_reviewed_git_result/example.ex",
  __DIR__
)

defmodule Jido.Realm.Host.Examples.ResumeJob do
  @moduledoc "Publish the verified report from a completed job after the host has retired its lease."

  alias Jido.Realm.Host
  alias Jido.Realm.Host.CommandRef
  alias Jido.Realm.Host.Examples.PublishReviewedGit

  def publish(reference, report_path, repo, expected_head) do
    with {:ok, command} <- CommandRef.parse(reference),
         {:ok, status} <- Host.recover_command(:recovery, command, :inspect),
         :ok <- require_success(status),
         {:ok, workspace} <- Host.open(profile: :run, infrastructure: command.infrastructure),
         {:ok, snapshot} <- save_and_close(workspace),
         {:ok, review} <- Host.open(profile: :review, from: snapshot),
         {:ok, report} <- read_and_close(review, report_path),
         :ok <- verify(report),
         {:ok, prepared} <- PublishReviewedGit.prepare(repo, expected_head, report),
         {:ok, commit} <- PublishReviewedGit.publish(repo, prepared) do
      {:ok, %{snapshot: snapshot, commit: commit}}
    end
  end

  defp require_success(%{status: :running}), do: {:error, :job_running}
  defp require_success(%{status: :exited, exit_status: 0}), do: :ok

  defp require_success(%{status: :exited, exit_status: status}),
    do: {:error, {:job_failed, status}}

  defp save_and_close(workspace) do
    result = Host.save(workspace)
    with :ok <- Host.close(workspace), do: result
  end

  defp read_and_close(workspace, path) do
    result = Host.read(workspace, path)
    with :ok <- Host.close(workspace), do: result
  end

  defp verify("complete\n"), do: :ok
  defp verify(_), do: {:error, :report_verification_failed}
end
