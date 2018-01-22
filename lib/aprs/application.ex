defmodule Aprs.Application do
  use Application

  def start(_, _) do
    import Supervisor.Spec

    children = [
      worker(Aprs, [])
    ]

    opts = [strategy: :one_for_one, name: Aprs.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
