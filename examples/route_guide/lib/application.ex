defmodule Routeguide.App do
  use Application

  @cert_path Path.expand("./tls/server1.pem", :code.priv_dir(:route_guide))
  @key_path Path.expand("./tls/server1.key", :code.priv_dir(:route_guide))

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(RouteGuide.DataHelper, []),
      supervisor(GRPC.Server.Supervisor, [start_args()])
    ]

    opts = [strategy: :one_for_one, name: Routeguide]
    Supervisor.start_link(children, opts)
  end

  defp start_args do
    if System.get_env("TLS") do
      cred = GRPC.Credential.new(ssl: [certfile: @cert_path, keyfile: @key_path])
      IO.inspect(cred)
      {Routeguide.Endpoint, 10000, cred: cred}
    else
      {Routeguide.Endpoint, 10000}
    end
  end
end
