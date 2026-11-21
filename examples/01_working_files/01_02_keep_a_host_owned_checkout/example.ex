defmodule Jido.Realm.Host.Examples.EditCheckout do
  alias Jido.Realm.Host

  def revise_draft(workspace, text) do
    with :ok <- Host.write(workspace, "draft.txt", text) do
      Host.run(workspace, ["cat", "draft.txt"])
    end
  end
end
