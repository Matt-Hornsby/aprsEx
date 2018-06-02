defmodule Aprs do
  use GenServer
  require Logger
  alias Aprs.Parser

  @aprs_timeout 30 * 1000

  # Initialization

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_args) do
    # Get startup parameters
    server = Application.get_env(:aprs, :server, 'rotate.aprs2.net')
    port = Application.get_env(:aprs, :port, 14580)
    default_filter = Application.get_env(:aprs, :default_filter, "r/47.6/-122.3/100")
    aprs_user_id = Application.get_env(:aprs, :login_id, "CHANGE_ME")
    aprs_passcode = Application.get_env(:aprs, :password, "-1")

    # Set up ets tables
    message_number_table = :ets.new(:message_number, [:set, :protected])
    :ets.insert(message_number_table, {"last_message_number", 0})

    with {:ok, socket} <- connect_to_aprs_is(server, port),
         :ok <- send_login_string(socket, aprs_user_id, aprs_passcode, default_filter),
         timer <- create_timer(@aprs_timeout) do
      {:ok,
       %{
         server: server,
         port: port,
         socket: socket,
         timer: timer,
         message_number_table: message_number_table
       }}
    else
      _ ->
        Logger.error("Unable to establish connection or log in to APRS-IS")
        {:stop, :aprs_connection_failed}
    end
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
    GenServer.call(__MODULE__, {:send_message, message})
  end

  # Server methods

  defp connect_to_aprs_is(server, port) do
    Logger.debug("Attempting to connect to #{server}:#{port}")
    opts = [:binary, active: true]
    :gen_tcp.connect(server, port, opts)
  end

  defp send_login_string(socket, aprs_user_id, aprs_passcode, filter) do
    login_string =
      "user #{aprs_user_id} pass #{aprs_passcode} vers aprsEx 0.1 filter #{filter} \n"

    :gen_tcp.send(socket, login_string)
  end

  defp create_timer(timeout) do
    Process.send_after(self(), :aprs_no_message_timeout, timeout)
  end

  def handle_call({:send_message, message}, _from, state) do
    next_ack_number = :ets.update_counter(state.message_number_table, "last_message_number", 1)
    # Append ack number
    message = message <> "{" <> to_string(next_ack_number) <> "\r"

    Logger.info("Sending message: #{inspect message}")
    :gen_tcp.send(state.socket, message)
    {:reply, :ok, state}
  end

  def handle_info(:aprs_no_message_timeout, state) do
    Logger.error("Socket timeout detected. Killing genserver.")
    {:stop, :aprs_timeout, state}
  end

  def handle_info({:tcp, _socket, packet}, state) do
    # Cancel the previous timer
    Process.cancel_timer(state.timer)

    # Handle the incoming message
    Task.start(Aprs, :dispatch, [packet])
    # dispatch(packet)

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
    Logger.error("Connection closed due to #{inspect(reason)}")
    {:stop, :normal, state}
  end

  def terminate(reason, state) do
    # Do Shutdown Stuff
    Logger.info("Going Down: #{inspect(reason)} - #{inspect(state)}")
    :gen_tcp.close(state.socket)
    :normal
  end

  def dispatch("#" <> comment_text) do
    Logger.debug("COMMENT:" <> String.trim(comment_text))
  end

  def dispatch(message) do
    IO.inspect(message)
    parsed_message = Parser.parse(message)

    Registry.dispatch(Registry.PubSub, "aprs_messages", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, parsed_message})
    end)

    IO.inspect(parsed_message)
    Logger.debug("SERVER:" <> message)
  end
end
