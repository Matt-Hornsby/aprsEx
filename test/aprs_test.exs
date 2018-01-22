defmodule AprsTest do
  use ExUnit.Case
  doctest Aprs

  test "timestamped position" do
    aprs_message = "KE7XXX>APRS,TCPIP*,qAC,NINTH:@211743z4444.67N/11111.68W_061/005g012t048r000p000P000h77b10015.DsVP\r\n"
    sut = Parser.parse(aprs_message)
    assert sut.data_type == :timestamped_position_with_message
  end

end
