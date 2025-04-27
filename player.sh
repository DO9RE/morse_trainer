#!/usr/bin/env bash

# Name der Named Pipe
FIFO_FILE="/tmp/audio_fifo"

# Frequenz und Längen für Morsezeichen
DOT_LENGTH=0.1  # Länge eines Punktes
DASH_LENGTH=0.3 # Länge eines Strichs
PAUSE_LENGTH=0.1 # Pause zwischen Zeichen
CHAR_PAUSE=0.1   # Pause zwischen jedem Zeichen
TONE_FREQ=800    # Frequenz des Tons
SAMPLE_RATE=32000 # Abtastrate für den Ton

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
AUDIODEV=hw:0 play --buffer 1024 -q -t raw -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer "$FIFO_FILE" &

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
                sox -n -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer -t raw - synth "$DOT_LENGTH" sine "$TONE_FREQ" > "$FIFO_FILE"
                # Add pause after dot
                sox -n -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer -t raw - trim 0 "$CHAR_PAUSE" > "$FIFO_FILE"
                ;;
            "-")
                # Strich abspielen
                sox -n -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer -t raw - synth "$DASH_LENGTH" sine "$TONE_FREQ" > "$FIFO_FILE"
                # Add pause after dash
                sox -n -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer -t raw - trim 0 "$CHAR_PAUSE" > "$FIFO_FILE"
                ;;
            " ")
                # Pause einfügen (word space in Morse is typically 3x character pause)
                sox -n -r "$SAMPLE_RATE" -b 16 -c 1 -e signed-integer -t raw - trim 0 $(echo "$PAUSE_LENGTH * 3" | bc) > "$FIFO_FILE"
                ;;
            *)
                echo "Ungültiges Zeichen: $char"
                ;;
        esac
    done
done
