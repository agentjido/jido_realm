defmodule Jido.Realm.Application do
  @moduledoc false
  use Application

  @doc "Starts the Realm controller supervisors and registries."
  def start(_, _) do
    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: Jido.Realm.Host.Sandbox.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Jido.Realm.Host.Sandbox.Supervisor},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Jido.Realm.Host.ProviderLease.Supervisor},
        {Task.Supervisor, name: Jido.Realm.Host.ProfileSession.Tasks},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Jido.Realm.Host.ProfileSession.Supervisor},
        {Registry, keys: :unique, name: Jido.Realm.Host.Deploy.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Jido.Realm.Host.Deploy.Supervisor},
        {Task.Supervisor, name: Jido.Realm.Host.Deploy.Tasks}
      ],
      strategy: :one_for_one,
      name: Jido.Realm.Supervisor
    )
  end
end
