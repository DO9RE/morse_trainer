#!/usr/bin/env bash

# Name der Named Pipe
FIFO="/tmp/audio_fifo"

# Cleanup-Funktion
cleanup() {
    echo "Cleaning up..."
    [[ -p "$FIFO" ]] && rm -f "$FIFO"
    exit 0
}
trap cleanup INT TERM EXIT

# Named Pipe erstellen
if [[ ! -p "$FIFO" ]]; then
    mkfifo "$FIFO"
fi

play -q -t raw -r 44100 -e signed-integer -b 16 -c 1 "$FIFO"


# Endlosschleife zum Einlesen der Benutzereingaben
while true; do
    read -n1 INPUT  # Lies genau 1 Zeichen

    case "$INPUT" in
        ".")
            # Kurzer Piepton (z.B. 0.1 Sekunden, 880 Hz)
            sox -n -r 44100 -e signed-integer -b 16 -c 1 -t raw synth 0.1 sine 440 - > "$FIFO"
            ;;
        "-")
            # Langer Piepton (z.B. 0.5 Sekunden, 440 Hz)
sox -n -r 44100 -e signed-integer -b 16 -c 1 -t raw - synth 0.1 sine 440 pad 0 0.1 > "$FIFO"
#            sox -n -r 44100 -e signed-integer -b 16 -c 1 -t raw synth 0.5 sine 440 > "$FIFO"
            ;;
        "q")
            echo "Beende..."
            kill "$PLAY_PID"
            rm "$FIFO"
            exit 0
            ;;
        *)
            echo "Ungültige Eingabe. Drücke '.' oder '-' oder 'q'."
            ;;
    esac
done
