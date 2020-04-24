use Mix.Config

config :aprs_ex,
  # Use this if you have the local aprs simulator app running:
  # server: 'localhost',
  # port: 4040,
  # Connect to aprs-is server
  server: 'rotate.aprs2.net',
  port: 14580,
  default_filter: "r/47.6/-122.3/100",
  login_id: System.get_env("APRS_CALLSIGN"),
  password: System.get_env("APRS_PASSCODE")
