defmodule Aprs.Parser do
  use Bitwise
  alias Aprs.Types.Mic_e

  def parse(message) do
    [sender, path, data] = String.split(message, [">", ":"], parts: 3)
    [base_callsign, ssid] = parse_callsign(sender)
    data_type = String.first(data) |> parse_datatype

    data = String.trim(data)
    [destination, path] = String.split(path, ",", parts: 2)
    data_extended = parse_data(data_type, destination, data)

    %{
      sender: sender,
      path: path,
      destination: destination,
      information_field: data,
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

  def parse_data(:timestamped_position_with_message, _destination, data),
    do: parse_position_with_timestamp(true, data)

  def parse_data(
        :timestamped_position_with_message,
        _destination,
        <<_dti::binary-size(1), date_time_position::binary-size(25), "_", weather_report::binary>>
      ) do
    parse_position_with_datetime_and_weather(true, date_time_position, weather_report)
  end

  def parse_data(
        :message,
        destination,
        <<":", addressee::binary-size(9), ":", message_text::binary>>
      ) do
    # Aprs messages can have an optional message number tacked onto the end
    # for the purposes of acknowledging message receipt.
    # The sender tacks the message number onto the end of the message,
    # and the receiving station is supposed to respond back with an 
    # acknowledgement of that message number.
    # Example
    # Sender: Hello world{123
    # Receiver: ack123
    # Special thanks to Jeff Smith(https://github.com/electricshaman) for the regex
    regex = ~r/^(?<message>.*?)(?:{(?<message_number>\w+))?$/i
    result = find_matches(regex, message_text)

    %{
      to: String.trim(addressee),
      message_text: String.trim(result["message"]),
      message_number: result["message_number"]
    }
  end

  def parse_data(_type, _destination, _data), do: nil

  def parse_position_with_datetime_and_weather(
        aprs_messaging?,
        date_time_position_data,
        weather_report
      ) do
    <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1),
      longitude::binary-size(9)>> = date_time_position_data

    position = Aprs.Types.Position.from_aprs(latitude, longitude)

    %{
      position: position,
      timestamp: time,
      symbol_table_id: sym_table_id,
      symbol_code: "_",
      weather: weather_report,
      data_type: :position_with_datetime_and_weather,
      aprs_messaging?: aprs_messaging?
    }
  end

  def decode_compressed_position(
        <<"/", latitude::binary-size(4), longitude::binary-size(4), symbol::binary-size(1),
          cs::binary-size(2), compression_type::binary-size(2), rest::binary>>
      ) do
    lat = convert_to_base91(latitude)
    lon = convert_to_base91(longitude)
    [:ok, lat, lon]
  end

  defp convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    (v1 - 33) * 91 * 91 * 91 + (v2 - 33) * 91 * 91 + (v3 - 33) * 91 + v4
  end

  def parse_position_without_timestamp(aprs_messaging?, <<"!!", rest::binary>>) do
    # this is an ultimeter weather station. need to parse its weird format
    "TODO: PARSE ULTIMETER DATA"
  end

  def parse_position_without_timestamp(
        aprs_messaging?,
        <<_dti::binary-size(1), "/", latitude::binary-size(4), longitude::binary-size(4),
          sym_table_id::binary-size(1), cs::binary-size(2), compression_type::binary-size(1),
          comment::binary>>
      ) do
    "TODO: PARSE COMPRESSED LAT/LON"
  end

  def parse_position_without_timestamp(
        aprs_messaging?,
        <<_dti::binary-size(1), latitude::binary-size(8), sym_table_id::binary-size(1),
          longitude::binary-size(9), symbol_code::binary-size(1), comment::binary>>
      ) do
    position = Aprs.Types.Position.from_aprs(latitude, longitude)

    %{
      position: position,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: aprs_messaging?
    }
  end

  def parse_position_with_timestamp(
        aprs_messaging?,
        <<_dti::binary-size(1), time::binary-size(7), latitude::binary-size(8),
          sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
          comment::binary>>
      ) do
    position = Aprs.Types.Position.from_aprs(latitude, longitude)

    %{
      position: position,
      time: time,
      symbol_table_id: sym_table_id,
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

    information_data =
      parse_mic_e_information(information_field, destination_data.longitude_offset)

    %Mic_e{
      lat_degrees: destination_data.lat_degrees,
      lat_minutes: destination_data.lat_minutes,
      lat_fractional: destination_data.lat_fractional,
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
      speed: information_data.speed,
      manufacturer: information_data.manufacturer,
      message: information_data.message
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
    fractional = digits |> Enum.slice(4..5) |> Enum.join() |> String.to_integer()

    [ns, lo, ew] = destination_field |> to_charlist |> Enum.slice(3..5)

    north_south_indicator =
      case ns do
        x when x in ?0..?9 -> :south
        x when x == ?L -> :south
        x when x in ?P..?Z -> :north
        _ -> :unknown
      end

    east_west_indicator =
      case ew do
        x when x in ?0..?9 -> :east
        x when x == ?L -> :east
        x when x in ?P..?Z -> :west
        _ -> :unknown
      end

    longitude_offset =
      case lo do
        x when x in ?0..?9 -> 0
        x when x == ?L -> 0
        x when x in ?P..?Z -> 100
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
      lat_fractional: fractional,
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
          message::binary>> = _information_field,
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

    # Messages should at least have a starting and ending symbol, and an optional message in between
    # But, there might not be any symbols either, so it could look like any of the following:
    # >^  <- TH-D74
    # nil <- who knows
    # ]\"55}146.820 MHz T103 -0600= <- Kenwood DM-710

    regex = ~r/^(?<first>.?)(?<msg>.*)(?<secondtolast>.)(?<last>.)$/i
    result = find_matches(regex, message)

    symbol1 =
      if result["first"] == "" do
        result["secondtolast"]
      else
        result["first"]
      end

    manufacturer = parse_manufacturer(symbol1, result["secondtolast"], result["last"])

    %{
      dti: dti,
      lon_degrees: d28 - 28 + longitude_offset,
      lon_minutes: m,
      lon_fractional: f28 - 28,
      speed: dc,
      heading: heading,
      symbol: symbol,
      table: table,
      manufacturer: manufacturer,
      message: message
    }
  end

  def parse_manufacturer(" ", _s2, _s3), do: "Original MIC-E"
  def parse_manufacturer(">", _s2, "="), do: "Kenwood TH-D72"
  def parse_manufacturer(">", _s2, "^"), do: "Kenwood TH-D74"
  def parse_manufacturer(">", _s2, _s3), do: "Kenwood TH-D74A"
  def parse_manufacturer("]", _s2, "="), do: "Kenwood DM-710"
  def parse_manufacturer("]", _s2, _s3), do: "Kenwood DM-700"
  def parse_manufacturer("`", "_", " "), do: "Yaesu VX-8"
  def parse_manufacturer("`", "_", "\""), do: "Yaesu FTM-350"
  def parse_manufacturer("`", "_", "#"), do: "Yaesu VX-8G"
  def parse_manufacturer("`", "_", "$"), do: "Yaesu FT1D"
  def parse_manufacturer("`", "_", "%"), do: "Yaesu FTM-400DR"
  def parse_manufacturer("`", "_", ")"), do: "Yaesu FTM-100D"
  def parse_manufacturer("`", "_", "("), do: "Yaesu FT2D"
  def parse_manufacturer("`", " ", "X"), do: "AP510"
  def parse_manufacturer("`", _s2, _s3), do: "Mic-Emsg"
  def parse_manufacturer("'", "|", "3"), do: "Byonics TinyTrack3"
  def parse_manufacturer("'", "|", "4"), do: "Byonics TinyTrack4"
  def parse_manufacturer("'", ":", "4"), do: "SCS GmbH & Co. P4dragon DR-7400 modems"
  def parse_manufacturer("'", ":", "8"), do: "SCS GmbH & Co. P4dragon DR-7800 modems"
  def parse_manufacturer("'", _s2, _s3), do: "McTrackr"
  def parse_manufacturer(_s1, "\"", _s3), do: "Hamhud ?"
  def parse_manufacturer(_s1, "/", _s3), do: "Argent ?"
  def parse_manufacturer(_s1, "^", _s3), do: "HinzTec anyfrog"
  def parse_manufacturer(_s1, "*", _s3), do: "APOZxx www.KissOZ.dk Tracker. OZ1EKD and OZ7HVO"
  def parse_manufacturer(_s1, "~", _s3), do: "Other"
  def parse_manufacturer(_symbol1, _symbol2, _symbol3), do: :unknown_manufacturer

  defp find_matches(regex, text) do
    case Regex.names(regex) do
      [] ->
        matches = Regex.run(regex, text)

        Enum.reduce(Enum.with_index(matches), %{}, fn {match, index}, acc ->
          Map.put(acc, index, match)
        end)

      _ ->
        Regex.named_captures(regex, text)
    end
  end
end
