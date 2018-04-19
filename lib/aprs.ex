defmodule Aprs do
  use GenServer
  require Logger
  alias Aprs.Parser

  @aprs_timeout 30 * 1000

  # Initialization

  def start_link do
    server = Application.get_env(:aprs, :server, 'rotate.aprs.net')
    port = Application.get_env(:aprs, :port, 14580)
    default_filter = Application.get_env(:aprs, :default_filter, "r/47.6/-122.3/100")
    GenServer.start_link(__MODULE__, [server, port, default_filter], name: __MODULE__)
  end

  def init([server, port, default_filter]) do
    aprs_user_id = Application.get_env(:aprs, :login_id, "CHANGE_ME")
    aprs_passcode = Application.get_env(:aprs, :password, "-1")

    Logger.debug("Attempting to connect to #{server}:#{port}")

    opts = [:binary, active: true]
    {:ok, socket} = :gen_tcp.connect(server, port, opts)

    Logger.debug("Connection established")

    login_string =
      "user #{aprs_user_id} pass #{aprs_passcode} vers aprsEx 0.1 filter #{default_filter} \n"

    Logger.debug("Logging into #{server}:#{port} with string: #{login_string}")
    :gen_tcp.send(socket, login_string)

    timer = Process.send_after(self(), :aprs_no_message_timeout, @aprs_timeout)
    {:ok, %{server: server, port: port, socket: socket, timer: timer}}
  end

  # Client API

  def stop() do
    Logger.info("Stopping Server")
    GenServer.stop(__MODULE__, :stop)
  end

  def set_filter(filter_string), do: send_message("#filter #{filter_string}")
  def list_active_filters(), do: send_message("#filter?")

  def send_message(from, to, message) do
    padded_callsign = String.pad_trailing(to, 9)
    send_message("#{from}>APRS,TCPIP*::#{padded_callsign}:#{message}")
  end

  def send_message(message) do
    GenServer.call(__MODULE__, {:send_message, message <> "\r"})
  end

  # Server methods

  def handle_call({:send_message, message}, _from, state) do
    Logger.info("Sending message: #{message}")
    :gen_tcp.send(state.socket, message)
    {:reply, :ok, state}
  end

  def handle_info(:aprs_no_message_timeout, state) do
    Logger.info("Socket timeout detected. Killing genserver.")
    {:stop, :apts_timeout, state}
  end

  def handle_info({:tcp, _socket, packet}, state) do
    # Cancel the previous timer
    Process.cancel_timer(state.timer)

    # Handle the incoming message
    dispatch(packet)

    # Start a new timer
    timer = Process.send_after(self(), :aprs_no_message_timeout, @aprs_timeout)
    state = Map.put(state, :timer, timer)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Socket has been closed")
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    IO.inspect(socket, label: "connection closed due to #{reason}")
    {:stop, :normal, state}
  end

  def terminate(reason, state) do
    # Do Shutdown Stuff
    Logger.info("Going Down: #{inspect(reason)} - #{inspect(state)}")
    :gen_tcp.close(state.socket)
    :normal
  end

  defp dispatch("#" <> comment_text) do
    Logger.debug("COMMENT:" <> String.trim(comment_text))
  end

  defp dispatch(message) do
    parsed_message = Parser.parse(message)

    Registry.dispatch(Registry.PubSub, "aprs_messages", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, parsed_message})
    end)

    IO.inspect(parsed_message)
    Logger.debug("SERVER:" <> message)
  end
end
