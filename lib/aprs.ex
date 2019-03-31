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
    # Trap exits so we can gracefully shut down
    Process.flag(:trap_exit, true)

    # Get startup parameters
    server = Application.get_env(:aprs, :server, 'rotate.aprs2.net')
    port = Application.get_env(:aprs, :port, 14580)
    default_filter = Application.get_env(:aprs, :default_filter, "r/47.6/-122.3/100")
    aprs_user_id = Application.get_env(:aprs, :login_id, "CHANGE_ME")
    aprs_passcode = Application.get_env(:aprs, :password, "-1")

    # Set up ets tables

    with {:ok, :aprs} <- :ets.file2tab(:erlang.binary_to_list("priv/aprs.ets")),
         {:ok, :aprs_messages} <- :ets.file2tab(:erlang.binary_to_list("priv/aprs_messages.ets")) do
    else
      {:error, _reason} ->
        Logger.debug("Ets files not found. Creating new ETS tables.")
        # Create new ETS tables
        :ets.new(:aprs, [:set, :protected, :named_table])
        :ets.new(:aprs_messages, [:bag, :protected, :named_table])

        # Write them to file here in case genserver is brutally terminated
        :ets.tab2file(:aprs, :erlang.binary_to_list("priv/aprs.ets"))
        :ets.tab2file(:aprs_messages, :erlang.binary_to_list("priv/aprs_messages.ets"))

      _ ->
        Logger.error("Unable to set up ETS tables for message storage.")
    end

    # TODO: Split out the APRS server connectivity into a different process
    # so that it can be interacted with separately from the message processing.
    with {:ok, socket} <- connect_to_aprs_is(server, port),
         :ok <- send_login_string(socket, aprs_user_id, aprs_passcode, default_filter),
         timer <- create_timer(@aprs_timeout) do
      {:ok,
       %{
         server: server,
         port: port,
         socket: socket,
         timer: timer
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
    next_ack_number = :ets.update_counter(:aprs, :message_number, 1)
    # Append ack number
    message = message <> "{" <> to_string(next_ack_number) <> "\r"

    Logger.info("Sending message: #{inspect(message)}")
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
    # TODO: Spawn a process/genserver to handle the ETS functionality
    # Task.start(Aprs, :dispatch, [packet])
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
    Logger.error("Connection closed due to #{inspect(reason)}")
    {:stop, :normal, state}
  end

  def terminate(reason, state) do
    # Do Shutdown Stuff
    Logger.info("Going Down: #{inspect(reason)} - #{inspect(state)}")
    Logger.info("Attempting to write ets tables to disk.")
    :ets.tab2file(:aprs, :erlang.binary_to_list("priv/aprs.ets"))
    :ets.tab2file(:aprs_messages, :erlang.binary_to_list("priv/aprs_messages.ets"))

    Logger.info("Closing socket")
    :gen_tcp.close(state.socket)

    :normal
  end

  def dispatch("#" <> comment_text) do
    Logger.debug("COMMENT:" <> String.trim(comment_text))
  end

  def dispatch(message) do
    IO.inspect(message)
    parsed_message = Parser.parse(message)

    time_message_received =
      :calendar.universal_time() |> :calendar.datetime_to_gregorian_seconds()

    # This doesnt work if dispatch if spawned as a task, since it does not own the table
    :ets.insert(:aprs, {parsed_message.sender, message, time_message_received})

    # Get messages since last time the callsign was seen
    # TODO: Get last seen timestamp and use that
    message_count =
      case :ets.lookup(:aprs_messages, parsed_message.sender) do
        [{_callsign, _message, timestamp}] ->
          recent_messages_for(parsed_message.sender, timestamp)

        [] ->
          0

        _ ->
          0
      end

    Logger.debug("#{message_count} recent messages for #{parsed_message.sender}")

    # Do something interesting with the message
    process(parsed_message, parsed_message.data_type)

    # Publish the parsed message to all interested parties
    Registry.dispatch(Registry.PubSub, "aprs_messages", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, parsed_message})
    end)

    IO.inspect(parsed_message)
    Logger.debug("SERVER:" <> message)
  end

  def process(message, message_type) when message_type == :message do
    time_message_received =
      :calendar.universal_time() |> :calendar.datetime_to_gregorian_seconds()

    :ets.insert(
      :aprs_messages,
      {message.data_extended.to, message.data_extended, time_message_received}
    )
  end

  def process(_, _), do: nil

  def recent_messages_for(callsign, since_time) do
    callsign_guard = {:==, :"$1", {:const, callsign}}
    timestamp_guard = {:>=, :"$2", {:const, since_time}}
    total_spec = [{{:"$1", :_, :"$2"}, [{:andalso, callsign_guard, timestamp_guard}], [true]}]
    :ets.select_count(:aprs_messages, total_spec)
  end
end
