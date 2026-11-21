defmodule Jido.Realm.Host.Examples.EditProject do
  @moduledoc "Prepare a project and move a draft into review."

  alias Jido.Realm.Host

  def prepare_review(workspace, draft) do
    with :ok <- Host.mkdir(workspace, "project/inbox"),
         :ok <- Host.mkdir(workspace, "project/review"),
         :ok <- Host.write(workspace, "project/inbox/draft.txt", draft),
         :ok <- Host.move(workspace, "project/inbox/draft.txt", "project/review/draft.txt"),
         :ok <- Host.delete(workspace, "project/inbox"),
         {:ok, draft} <- Host.read(workspace, "project/review/draft.txt"),
         {:ok, entries} <- Host.list(workspace, "project/review") do
      {:ok, draft, entries}
    end
  end
end
