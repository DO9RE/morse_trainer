#!/usr/bin/env bash

SOCKET_PORT=12345
SOX_CMD="play -q -t wav -" # SoX-Befehl für WAV-Daten

# Cleanup für Hintergrundprozesse
cleanup() {
    echo "Cleaning up socat and background processes..."
    pkill -P $$ > /dev/null 2>&1
    exit 0
}
trap cleanup INT TERM

# Starte den Audio-Kanal mit socat
start_audio_channel() {
    echo "Starte Audio-Wiedergabe-Kanal mit socat auf Port $SOCKET_PORT..."
    socat -u TCP-LISTEN:$SOCKET_PORT,reuseaddr,fork EXEC:"$SOX_CMD" &
    SOCAT_PID=$!
}

# Funktion zum Generieren von Tönen und Senden an den Socket
play_tone() {
    local frequency="$1"
    local duration="$2"

    # Generiere den Ton als WAV-Daten und sende ihn über den Socket
    sox -n -r 44100 -b 16 -c 1 -t wav - synth "$duration" sine "$frequency" | socat - TCP:localhost:$SOCKET_PORT
}

# Test: Morsecode für "SOS" senden
send_morse_sos() {
    echo "Sende SOS als Morsecode..."

    local DOT_LENGTH=0.2  # Länge eines Punktes
    local DASH_LENGTH=0.6 # Länge eines Strichs
    local PAUSE_SYMBOL=0.2  # Pause zwischen Symbolen
    local FREQUENCY=600  # Frequenz des Tons in Hz

    # "SOS" ist "... --- ..."
    for char in "." "." "." "-" "-" "-" "." "." "."; do
        if [[ "$char" == "." ]]; then
            play_tone "$FREQUENCY" "$DOT_LENGTH"
        elif [[ "$char" == "-" ]]; then
            play_tone "$FREQUENCY" "$DASH_LENGTH"
        fi

        # Pause zwischen Symbolen
        perl -e "select(undef, undef, undef, $PAUSE_SYMBOL);"
    done

    echo "SOS gesendet!"
}

# Starte den Audio-Kanal
start_audio_channel

# Testweise Morsecode senden
send_morse_sos

# Endlosschleife, um das Skript aktiv zu halten
while true; do
    sleep 1
done
