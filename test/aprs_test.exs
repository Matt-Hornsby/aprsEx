defmodule AprsTest do
  use ExUnit.Case
  alias Aprs.Parser
  doctest Aprs

  test "timestamped position" do
    aprs_message =
      "KE7XXX>APRS,TCPIP*,qAC,NINTH:@211743z4444.67N/11111.68W_061/005g012t048r000p000P000h77b10015.DsVP\r\n"

    sut = Parser.parse(aprs_message)
    assert sut.data_type == :timestamped_position_with_message
  end

  test "mic_e convert digits" do
    sut = Parser.parse_mic_e_digit("0")
    assert sut == [0, 0, nil]
  end

  test "mic_e convert destination field" do
    sut = Parser.parse_mic_e_destination("T7SYWP")

    assert sut == %{
             lat_degrees: 47,
             lat_minutes: 39,
             lat_fractional: 70,
             lat_direction: :north,
             lon_direction: :west,
             longitude_offset: 100,
             message_code: "M02",
             message_description: "In Service"
           }
  end

  test "mic_e convert information field" do
    information_field = ~s(`\(_fn"Oj/]TEST=)
    sut = Parser.parse_mic_e_information(information_field, 100)

    assert sut ==
             %{
               dti: "`",
               heading: 251,
               lon_degrees: 112,
               lon_fractional: 74,
               lon_minutes: 7,
               speed: 20,
               symbol: "j",
               table: "/",
               message: "]TEST=",
               manufacturer: "Kenwood DM-710"
             }
  end

  test "mic_e" do
    sut = Aprs.Parser.parse_mic_e("T7SYWP", ~s(`\(_fn"Oj/))
    assert %Aprs.Types.Mic_e{} = sut
  end
end
