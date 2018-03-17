defmodule Parser do
  def parse(message) do
    [callsign, path, data] = String.split(message, [">", ":"], parts: 3)
    [base_callsign, ssid] = parse_callsign(callsign)
    data_type = String.first(data) |> parse_datatype

    %{
      callsign: callsign,
      path: path,
      data: data,
      data_type: data_type,
      base_callsign: base_callsign,
      ssid: ssid,
      data_extended: parse_data(data)
    }
  end

  def parse_callsign(callsign) do
    if String.contains?(callsign, "-") do
      String.split(callsign, "-")
    else
      [callsign, nil]
    end
  end

  # One of the nutty exceptions in the APRS protocol has to do with this
  # data type indicator. It's usually the first character of the message.
  # However, in some rare cases, the ! indicator can be anywhere in the
  # first 40 characters of the message. I'm not going to deal with that
  # weird case right now. It seems like its for a specific type of old
  # TNC hardware that probably doesn't even exist anymore.
  def parse_datatype(datatype) when datatype == ":", do: :message
  def parse_datatype(datatype) when datatype == ">", do: :status
  def parse_datatype(datatype) when datatype == "!", do: :position
  def parse_datatype(datatype) when datatype == "/", do: :timestamped_position
  def parse_datatype(datatype) when datatype == "=", do: :position_with_message
  def parse_datatype(datatype) when datatype == "@", do: :timestamped_position_with_message
  def parse_datatype(datatype) when datatype == ";", do: :object
  def parse_datatype(datatype) when datatype == "`", do: :mic_e
  def parse_datatype(datatype) when datatype == "'", do: :mic_e_old

  def parse_datatype(_datatype), do: :unknown

  def parse_data(<<"!", rest::binary>>), do: parse_position_without_timestamp(false, rest)
  def parse_data(<<"=", rest::binary>>), do: parse_position_without_timestamp(true, rest)
  def parse_data(<<"/", rest::binary>>), do: parse_position_with_timestamp(false, rest)

  #"@230355z4739.10N/12224.32W_182/001g006t043r000p015P015h86b10237l478.DsVP"
  def parse_data(<<"@", date_time_position::binary-size(25), "_", weather_report::binary>>) do 
    parse_position_with_datetime_and_weather(true, date_time_position, weather_report)
  end
  def parse_data(<<"@", rest::binary>>), do: parse_position_with_timestamp(true, rest)
  def parse_data(_data), do: nil

  def parse_position_with_datetime_and_weather(aprs_messaging?, date_time_position_data, weather_report) do
    <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9)>> = date_time_position_data
    %{
      latitude: latitude,
      symbol_table_id: sym_table_id,
      longitude: longitude,
      symbol_code: "_",
      weather: weather_report,
      data_type: :position_with_datetime_and_weather,
      aprs_messaging?: aprs_messaging?
    }
  end

  def parse_position_without_timestamp(
        aprs_messaging?,
        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9),
          symbol_code::binary-size(1), comment::binary>>
      ) do
    %{
      latitude: latitude,
      symbol_table_id: sym_table_id,
      longitude: longitude,
      symbol_code: symbol_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: aprs_messaging?
    }
  end

  def parse_position_with_timestamp(
        aprs_messaging?,
        <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1),
          longitude::binary-size(9), symbol_code::binary-size(1), comment::binary>>
      ) do
    %{
      time: time,
      latitude: latitude,
      symbol_table_id: sym_table_id,
      longitude: longitude,
      symbol_code: symbol_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: aprs_messaging?
    }
  end
end
