#!/bin/bash

# Überprüfen, ob sox installiert ist
if ! command -v sox &> /dev/null; then
    echo "Fehler: 'sox' ist nicht installiert. Bitte installieren Sie es zuerst."
    exit 1
fi

# Plattform erkennen
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="mac"
else
    echo "Fehler: Dieses Betriebssystem wird nicht unterstützt."
    exit 1
fi

# Temporäre Dateien für Morse-Töne
DOT_FILE="/tmp/morse_dot.wav"
DASH_FILE="/tmp/morse_dash.wav"

# Morse-Töne erzeugen (nur einmal)
if [[ ! -f "$DOT_FILE" ]]; then
    echo "Erzeuge Morse-Punkt..."
    sox -n -r 44100 -c 1 -b 16 "$DOT_FILE" synth 0.1 sine 700
fi

if [[ ! -f "$DASH_FILE" ]]; then
    echo "Erzeuge Morse-Strich..."
    sox -n -r 44100 -c 1 -b 16 "$DASH_FILE" synth 0.3 sine 700
fi

# Read-Schleife für Benutzereingabe
echo "Drücke '.' für Punkt oder '-' für Strich. Zum Beenden 'q' drücken."
while true; do
    read -n 1 -s key  # Liest ein einzelnes Zeichen ohne Enter
    case "$key" in
        ".")
            if [[ "$PLATFORM" == "linux" ]]; then
                AUDIODEV=hw:0 play "$DOT_FILE"
            elif [[ "$PLATFORM" == "mac" ]]; then
                afplay "$DOT_FILE"
            fi
            ;;
        "-")
            if [[ "$PLATFORM" == "linux" ]]; then
                AUDIODEV=hw:0 play "$DASH_FILE"
            elif [[ "$PLATFORM" == "mac" ]]; then
                afplay "$DASH_FILE"
            fi
            ;;
        "q")
            echo "Beende Programm."
            break
            ;;
        *)
            echo "Ungültige Taste. Benutze '.' oder '-' oder 'q' zum Beenden."
            ;;
    esac
done
