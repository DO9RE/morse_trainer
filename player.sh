#!/usr/bin/env bash

# Name der Named Pipe
FIFO_FILE="/tmp/audio_fifo"

# Frequenz und Längen für Morsezeichen
DOT_LENGTH=0.1  # Länge eines Punktes
DASH_LENGTH=0.3 # Länge eines Strichs
PAUSE_LENGTH=0.1 # Pause zwischen Zeichen
TONE_FREQ=800    # Frequenz des Tons

# Cleanup-Funktion
cleanup() {
    echo "Beende und räume auf..."
    [[ -p "$FIFO_FILE" ]] && rm -f "$FIFO_FILE"
    exit 0
}
trap cleanup INT TERM EXIT

# Named Pipe erstellen
if [[ ! -p "$FIFO_FILE" ]]; then
    mkfifo "$FIFO_FILE"
fi

# Startet den Play-Prozess im Hintergrund
play --buffer 1024 -q -t wav -r 32000 -b 16 -c 1 "$FIFO_FILE" &
# Starte mbuffer als Ringpuffer und leite die Daten an play weiter
# mbuffer -q -m 1M < "$FIFO_FILE" | play -q -t wav -r 44100 -b 16 -c 1 - &


# Halte die Pipe offen mit tail
tail -f /dev/null > "$FIFO_FILE" &

# Morsezeichen in Echtzeit verarbeiten
while true; do
    # Benutzeraufforderung
    read -p "Gib Morsezeichen ein (. für Punkt, - für Strich, Leerzeichen für Pause, 'exit' zum Beenden): " input

    # Exit-Befehl prüfen
    if [[ "$input" == "exit" ]]; then
        cleanup
    fi

    # Morsezeichen verarbeiten
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            ".")
                # Punkt abspielen
                sox -n -r 32000 -b 16 -c 1 -t wav - synth "$DOT_LENGTH" sine "$TONE_FREQ" > "$FIFO_FILE"
                ;;
            "-")
                # Strich abspielen
                sox -n -r 32000 -b 16 -c 1 -t wav - synth "$DASH_LENGTH" sine "$TONE_FREQ" > "$FIFO_FILE"
                ;;
            " ")
                # Pause einfügen
                sleep "$PAUSE_LENGTH"
                ;;
            *)
                echo "Ungültiges Zeichen: $char"
                ;;
        esac
    done
done
