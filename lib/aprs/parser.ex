defmodule Aprs.Parser do
  use Bitwise
  alias Aprs.Types.Mic_e

  def parse(message) do
    [sender, path, data] = String.split(message, [">", ":"], parts: 3)
    [base_callsign, ssid] = parse_callsign(sender)
    data_type = String.first(data) |> parse_datatype

    # aprs_data = String.slice(data, 1..-1) |> String.trim
    data = String.trim(data)

    aprs_data =
      case data_type do
        :unknown_datatype ->
          data

        _ ->
          String.slice(data, 1..-1)
      end

    [destination, path] = String.split(path, ",", parts: 2)

    # Regex.match?(~r/^q[A-Z]{2}$/, "qAR") # match 3 digit q code exactly
    # Regex.replace((~r/q[A-Z]{2}/, "qAR", "") # removes any 3 character q code from the string
    # Regex.named_captures(~r/(?<q_code>^q[A-Z]{2}$)/, "qAR") # captures any q code into the q_code group (must match exactly)
    # Regex.named_captures(~r/(?<q_code>q[A-Z]{2})/, test) # capture the 3 digit q-code from anywhere in the string

    data_extended = parse_data(data_type, destination, aprs_data)

    %{
      sender: sender,
      path: path,
      destination: destination,
      information_field: data,
      data: String.trim(aprs_data),
      data_type: data_type,
      base_callsign: base_callsign,
      ssid: ssid,
      data_extended: data_extended
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
  def parse_datatype(datatype) when datatype == "_", do: :weather
  def parse_datatype(datatype) when datatype == "T", do: :telemetry
  def parse_datatype(datatype) when datatype == "$", do: :raw_gps_ultimeter
  def parse_datatype(datatype) when datatype == "<", do: :station_capabilities
  def parse_datatype(datatype) when datatype == "?", do: :query
  def parse_datatype(datatype) when datatype == ":", do: :message
  def parse_datatype(datatype) when datatype == "{", do: :user_defined
  def parse_datatype(datatype) when datatype == "}", do: :third_party_traffic

  def parse_datatype(_datatype), do: :unknown_datatype

  def parse_data(:mic_e, destination, data), do: parse_mic_e(destination, data)
  def parse_data(:mic_e_old, destination, data), do: parse_mic_e(destination, data)
  def parse_data(:position, _destination, data), do: parse_position_without_timestamp(false, data)

  def parse_data(:position_with_message, _destination, data),
    do: parse_position_without_timestamp(true, data)

  def parse_data(:timestamped_position, _destination, data),
    do: parse_position_with_timestamp(false, data)

  def parse_data(
        :timestamped_position_with_message,
        _destination,
        <<date_time_position::binary-size(25), "_", weather_report::binary>>
      ) do
    parse_position_with_datetime_and_weather(true, date_time_position, weather_report)
  end

  def parse_data(:timestamped_position_with_message, _destination, data),
    do: parse_position_with_timestamp(true, data)

  def parse_data(_type, _destination, _data), do: nil

  # "@230355z4739.10N/12224.32W_182/001g006t043r000p015P015h86b10237l478.DsVP"
  # def parse_data(<<"@", date_time_position::binary-size(25), "_", weather_report::binary>>) do 
  #   parse_position_with_datetime_and_weather(true, date_time_position, weather_report)
  # end
  # def parse_data(<<"@", rest::binary>>), do: parse_position_with_timestamp(true, rest)
  # def parse_data(_data), do: nil

  # def parse_data(<<"!", rest::binary>>), do: parse_position_without_timestamp(false, rest)
  # def parse_data(<<"=", rest::binary>>), do: parse_position_without_timestamp(true, rest)
  # def parse_data(<<"/", rest::binary>>), do: parse_position_with_timestamp(false, rest)

  # #"@230355z4739.10N/12224.32W_182/001g006t043r000p015P015h86b10237l478.DsVP"
  # def parse_data(<<"@", date_time_position::binary-size(25), "_", weather_report::binary>>) do 
  #   parse_position_with_datetime_and_weather(true, date_time_position, weather_report)
  # end
  # def parse_data(<<"@", rest::binary>>), do: parse_position_with_timestamp(true, rest)
  # def parse_data(_data), do: nil

  def parse_position_with_datetime_and_weather(
        aprs_messaging?,
        date_time_position_data,
        weather_report
      ) do
    <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1),
      longitude::binary-size(9)>> = date_time_position_data

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

  def parse_mic_e(destination_field, information_field) do
    # Mic-E is kind of a nutty compression scheme, APRS packs additional
    # information into the destination field when Mic-E encoding is used.
    # No other aprs packets use the destination field this way as far as i know.

    # The destination field contains the following information:
    # Latitude, message code, N/S & E/W indicators, longitude offset, digipath code
    destination_data = parse_mic_e_destination(destination_field)

    # TODO: Parse the rest of the information
    information_data =
      parse_mic_e_information(information_field, destination_data.longitude_offset)

    # [destination_data, information_data]
    %Mic_e{
      lat_degrees: destination_data.lat_degrees,
      lat_minutes: destination_data.lat_minutes,
      lat_seconds: destination_data.lat_seconds,
      lat_direction: destination_data.lat_direction,
      lon_direction: destination_data.lon_direction,
      longitude_offset: destination_data.longitude_offset,
      message_code: destination_data.message_code,
      message_description: destination_data.message_description,
      dti: information_data.dti,
      heading: information_data.heading,
      lon_degrees: information_data.lon_degrees,
      lon_minutes: information_data.lon_minutes,
      lon_fractional: information_data.lon_fractional,
      speed: information_data.speed
    }
  end

  def parse_mic_e_digit(<<c>>) when c in ?0..?9, do: [c - ?0, 0, nil]
  def parse_mic_e_digit(<<c>>) when c in ?A..?J, do: [c - ?A, 1, :custom]
  def parse_mic_e_digit(<<c>>) when c in ?P..?Y, do: [c - ?P, 1, :standard]

  def parse_mic_e_digit("K"), do: [0, 1, :custom]
  def parse_mic_e_digit("L"), do: [0, 0, nil]
  def parse_mic_e_digit("Z"), do: [0, 1, :standard]

  def parse_mic_e_digit(_c), do: [:unknown, :unknown, :unknown]

  def parse_mic_e_destination(destination_field) do
    digits =
      destination_field
      |> String.codepoints()
      |> Enum.map(&parse_mic_e_digit/1)
      |> Enum.map(&hd/1)

    deg = digits |> Enum.slice(0..1) |> Enum.join() |> String.to_integer()
    min = digits |> Enum.slice(2..3) |> Enum.join() |> String.to_integer()
    sec = digits |> Enum.slice(4..5) |> Enum.join() |> String.to_integer()

    [ns, lo, ew] = destination_field |> to_charlist |> Enum.slice(3..5)

    north_south_indicator =
      case ns do
        x when x in ?0..?9 -> :south
        x when x == ?L -> :south
        x when x in ?P..?Y -> :north
        _ -> :unknown
      end

    east_west_indicator =
      case ew do
        x when x in ?0..?9 -> :east
        x when x == ?L -> :east
        x when x in ?P..?Y -> :west
        _ -> :unknown
      end

    longitude_offset =
      case lo do
        x when x in ?0..?9 -> 0
        x when x == ?L -> 0
        x when x in ?P..?Y -> 100
        _ -> :unknown
      end

    statuses = [
      "Emergency",
      "Priority",
      "Special",
      "Committed",
      "Returning",
      "In Service",
      "En Route",
      "Off Duty"
    ]

    message_digits =
      destination_field
      |> String.codepoints()
      |> Enum.take(3)

    [_, message_bit_1, message_type] = parse_mic_e_digit(Enum.at(message_digits, 0))
    [_, message_bit_2, _] = parse_mic_e_digit(Enum.at(message_digits, 1))
    [_, message_bit_3, _] = parse_mic_e_digit(Enum.at(message_digits, 2))

    # Convert the bits to binary to get the array index
    index = message_bit_1 * 4 + message_bit_2 * 2 + message_bit_3
    # need to invert this from the actual array index
    display_index = to_string(7 - index) |> String.pad_leading(2, "0")

    [message_code, message_description] =
      case message_type do
        :standard ->
          ["M" <> display_index, Enum.at(statuses, index)]

        :custom ->
          ["C" <> display_index, "Custom-#{display_index}"]

        nil ->
          ["", Enum.at(statuses, index)]
      end

    %{
      lat_degrees: deg,
      lat_minutes: min,
      lat_seconds: sec,
      lat_direction: north_south_indicator,
      lon_direction: east_west_indicator,
      longitude_offset: longitude_offset,
      message_code: message_code,
      message_description: message_description
    }
  end

  def parse_mic_e_information(
        <<dti::binary-size(1), d28::integer, m28::integer, f28::integer, sp28::integer,
          dc28::integer, se28::integer, symbol::binary-size(1), table::binary-size(1),
          rest::binary>> = _information_field,
        longitude_offset
      ) do
    m =
      case m28 - 28 do
        x when x >= 60 -> x - 60
        x -> x
      end

    sp =
      case sp28 - 28 do
        x when x >= 80 -> x - 80
        x -> x
      end

    dc = dc28 - 28
    quotient = div(dc, 10)
    remainder = rem(dc, 10)
    dc = sp * 10 + quotient
    heading = (remainder - 4) * 100 + (se28 - 28)

    %{
      dti: dti,
      lon_degrees: d28 - 28 + longitude_offset,
      lon_minutes: m,
      lon_fractional: f28 - 28,
      speed: dc,
      heading: heading
    }
  end
end
