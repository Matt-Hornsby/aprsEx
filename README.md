# Aprs

Interact with APRS-IS servers. Send/receive APRS messages. Parse APRS packets.

## Run it

APRS-IS requires a callsign and a passcode. In order to send messages on the APRS network, you must be a licensed amateur radio operator with a valid callsign. You will also need a passcode generated if you intend to send messages over the radio. If you just want to listen in on packets, you don't need to provide a passcode.

This app expects the above secrets to be provided via two environment variables:

```
export APRS_CALLSIGN = "YOUR CALLSIGN"
export APRS_PASSCODE = "YOUR PASSCODE"
```

or

```
APRS_CALLSIGN=FOO APRS_PASSCODE=BAR iex -S mix
```

Once you are in the shell, start up the genserver:
```
Aprs.start_link
```

This will login to the APRS-IS system and you should start seeing packets flow in.

Make sure you update the APRS filter in `config.exs`, as this controls what packets you see. If you don't, you'll get whatever default filter I happened to leave in the config.exs file last time I pushed code.