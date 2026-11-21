defmodule Jido.Realm.Host.TestSupport.TargetCoverage do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Realm.Host.Deploy.OTP

  def start(target) do
    if :code.which(:jido_realm_deploy_target) == :cover_compiled do
      assert {:ok, {:ok, _}} = OTP.call(target, :cover, :start, [])
      beam = Application.app_dir(:jido_realm, "ebin/jido_realm_deploy_target.beam")

      assert {:ok, {:ok, :jido_realm_deploy_target}} =
               OTP.call(target, :cover, :compile_beam, [String.to_charlist(beam)])

      ExUnit.Callbacks.on_exit({__MODULE__, target.id}, fn -> export(target) end)
    end

    target
  end

  def export(target) do
    if :code.which(:jido_realm_deploy_target) == :cover_compiled do
      directory = System.get_env("JIDO_COVERAGE_DIR", Path.expand("cover/children"))
      File.mkdir_p!(directory)

      file =
        Path.join(
          directory,
          "child-#{System.pid()}-#{System.unique_integer([:positive])}.coverdata"
        )

      assert {:ok, :ok} = OTP.call(target, :cover, :export, [String.to_charlist(file)])
      assert File.stat!(file).size > 0
    end

    :ok
  end
end
