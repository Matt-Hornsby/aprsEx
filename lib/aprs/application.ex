defmodule Aprs.Application do
  use Application

  def start(_, _) do
    import Supervisor.Spec

    children = [
      {Registry, keys: :duplicate, name: Registry.PubSub, partitions: System.schedulers_online()},
      worker(Aprs, [])
    ]

    opts = [strategy: :one_for_one, name: Aprs.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
