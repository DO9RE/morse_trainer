#!/usr/bin/env bash

# Name der Named Pipe
FIFO_FILE="/tmp/audio_fifo"

# Cleanup-Funktion
cleanup() {
    echo "Cleaning up..."
    [[ -p "$FIFO_FILE" ]] && rm -f "$FIFO_FILE"
    exit 0
}
trap cleanup INT TERM EXIT

# Named Pipe erstellen
if [[ ! -p "$FIFO_FILE" ]]; then
    mkfifo "$FIFO_FILE"
fi

# Play-Befehl startet und liest kontinuierlich aus der Pipe
play -q -t wav -r 44100 -b 16 -c 1 "$FIFO_FILE" &

# Endlosschleife, um Töne und Pausen kontinuierlich zu generieren
sox -n -r 44100 -b 16 -c 1 -t wav - synth 0.1 sine 440 pad 0 0.1 repeat - > "$FIFO_FILE"
