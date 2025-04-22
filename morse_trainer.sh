#!/bin/bash

# Datei für Fortschritt
PROGRESS_FILE="morse_progress.txt"

# Standardgeschwindigkeit (WPM)
DEFAULT_WPM=20
WPM=$DEFAULT_WPM

# Morse-Code-Tabelle
declare -A MORSE_CODE=(
    [A]=".-" [B]="-..." [C]="-.-." [D]="-.."
    [E]="." [F]="..-." [G]="--." [H]="...."
    [I]=".." [J]=".---" [K]="-.-" [L]=".-.."
    [M]="--" [N]="-." [O]="---" [P]=".--."
    [Q]="--.-" [R]=".-." [S]="..." [T]="-"
    [U]="..-" [V]="...-" [W]=".--" [X]="-..-"
    [Y]="-.--" [Z]="--.." [AR]=".-.-."
)

# Fortschritt laden oder initialisieren
load_progress() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        LESSON=$(<"$PROGRESS_FILE")
    else
        LESSON=2
        echo "$LESSON" > "$PROGRESS_FILE"
    fi
}

# Fortschritt speichern
save_progress() {
    echo "$LESSON" > "$PROGRESS_FILE"
}

# Geschwindigkeit anpassen
calculate_timings() {
    local unit_length=$(echo "1.2 / $WPM" | bc -l)  # Einheit für einen Punkt in Sekunden

    DOT_LENGTH=$unit_length
    DASH_LENGTH=$(echo "$unit_length * 3" | bc -l)
    PAUSE_SYMBOL=$(echo "$unit_length * 1" | bc -l)
    PAUSE_LETTER=$(echo "$unit_length * 3" | bc -l)
    PAUSE_WORD=$(echo "$unit_length * 7" | bc -l)

    # Anzahl der Fünfergruppen basierend auf Geschwindigkeit
    case $WPM in
        5) GROUP_COUNT=10 ;;
        10) GROUP_COUNT=12 ;;
        15) GROUP_COUNT=15 ;;
        20) GROUP_COUNT=17 ;;
        25) GROUP_COUNT=18 ;;
        30) GROUP_COUNT=20 ;;
        *) GROUP_COUNT=10 ;;  # Standardwert
    esac
}

# Funktion für Morse-Ton
play_morse_tone() {
    local tone_freq=800  # Frequenz in Hz

    for (( i=0; i<${#1}; i++ )); do
        char="${1:$i:1}"
        if [[ "$char" == "." ]]; then
            AUDIODEV=hw:0 play -n synth "$DOT_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        elif [[ "$char" == "-" ]]; then
            AUDIODEV=hw:0 play -n synth "$DASH_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        fi
        sleep "$PAUSE_SYMBOL"
    done
    sleep "$PAUSE_LETTER"  # Pause zwischen Buchstaben
}

# Trainings-Einheit: Zeichen lernen
training_mode() {
    echo "Trainings-Einheit: Lernen Sie die Morsezeichen der aktuellen Lektion."
    echo "Drücken Sie Enter, um zum nächsten Zeichen zu wechseln. (Strg+C zum Beenden)"
    
    # Zeichen für die aktuelle Lektion auswählen
    local available_chars=("${!MORSE_CODE[@]}")
    available_chars=("${available_chars[@]:0:$LESSON}")

    for char in "${available_chars[@]}"; do
        echo "Zeichen: $char - Morse: ${MORSE_CODE[$char]}"
        play_morse_tone "${MORSE_CODE[$char]}"
        read -r -p "Weiter mit Enter..."
    done
    echo "Trainings-Einheit abgeschlossen."
}

# Menü zur Geschwindigkeitsanpassung
speed_menu() {
    echo "Geschwindigkeitsauswahl:"
    echo "1. 5 WPM (langsam)"
    echo "2. 10 WPM"
    echo "3. 15 WPM"
    echo "4. 20 WPM (Standard)"
    echo "5. 25 WPM"
    echo "6. 30 WPM (schnell)"
    read -r -p "Wählen Sie die Geschwindigkeit (1-6): " speed_choice

    case $speed_choice in
        1) WPM=5 ;;
        2) WPM=10 ;;
        3) WPM=15 ;;
        4) WPM=20 ;;
        5) WPM=25 ;;
        6) WPM=30 ;;
        *) echo "Ungültige Eingabe. Standardgeschwindigkeit von 20 WPM wird verwendet." ;;
    esac

    echo "Geschwindigkeit wurde auf $WPM WPM gesetzt."
    calculate_timings
}

# Hauptprogramm
main() {
    load_progress
    calculate_timings

    while true; do
        echo "Willkommen zum Morse-Trainer!"
        echo "1. Trainings-Einheit (Zeichen lernen)"
        echo "2. Lektion starten"
        echo "3. Geschwindigkeit anpassen (aktuell: $WPM WPM)"
        echo "4. Beenden"
        read -r -p "Wählen Sie eine Option (1-4): " option

        case $option in
            1)
                training_mode
                ;;
            2)
                echo "Aktuelle Lektion: $LESSON Zeichen."
                echo "Es werden $GROUP_COUNT Fünfergruppen abgespielt."

                # Zeichen für die Lektion auswählen
                local available_chars=("${!MORSE_CODE[@]}")
                available_chars=("${available_chars[@]:0:$LESSON}")

                # Einleitung mit dreimal "V"
                echo "Einleitung: Dreimal das Zeichen 'V' zur Einstimmung."
                for _ in {1..3}; do
                    play_morse_tone "${MORSE_CODE[V]}"
                done

                # Generiere die Fünfergruppen
                local groups=()
                for ((g=0; g<$GROUP_COUNT; g++)); do
                    local group=""
                    for ((i=0; i<5; i++)); do
                        group+="${available_chars[RANDOM % ${#available_chars[@]}]}"
                    done
                    groups+=("$group")
                done

                # Abspielen und gleichzeitig Benutzer-Eingabe ermöglichen
                echo "Hören Sie zu und geben Sie gleichzeitig ein! Trennen Sie Gruppen mit Leerzeichen."
                local input=""
                
                # Hintergrundprozess zur Tonausgabe
                (
                    for group in "${groups[@]}"; do
                        for char in $(echo "$group" | grep -o .); do
                            play_morse_tone "${MORSE_CODE[$char]}"
                        done
                        sleep "$PAUSE_WORD"  # Pause zwischen den Gruppen
                    done
                    # Abschlusszeichen "AR"
                    play_morse_tone "${MORSE_CODE[AR]}"
                ) &

                # Eingabe des Benutzers während der Tonausgabe
                read -r -p "Ihre Eingabe (Gruppen mit Leerzeichen trennen): " input

                # Hintergrundprozess warten lassen, falls nötig
                wait

                # Eingabe normalisieren (Großbuchstaben)
                input=$(echo "$input" | tr '[:lower:]' '[:upper:]')

                # Jede Gruppe separat prüfen
                local correct_groups=0
                local total_groups=${#groups[@]}
                local input_groups=($input)

                for ((i=0; i<total_groups; i++)); do
                    if [[ "${groups[i]}" == "${input_groups[i]:-}" ]]; then
                        echo "Gruppe $((i+1)): Korrekt (${groups[i]})"
                        ((correct_groups++))
                    else
                        echo "Gruppe $((i+1)): Falsch (Richtig: ${groups[i]})"
                    fi
                done

                # Gesamtergebnis anzeigen
                local percentage=$((correct_groups * 100 / total_groups))
                echo "Ergebnis: $correct_groups/$total_groups Gruppen korrekt ($percentage%)."

                # Lektion beenden oder wiederholen
                if ((percentage >= 90)); then
                    echo "Glückwunsch! Sie dürfen zur nächsten Lektion fortschreiten."
                    ((LESSON++))
                    save_progress
                    break
                else
                    echo "Bitte versuchen Sie es erneut."
                fi
                ;;
            3)
                speed_menu
                ;;
            4)
                echo "Auf Wiedersehen!"
                exit 0
                ;;
            *)
                echo "Ungültige Eingabe. Bitte versuchen Sie es erneut."
                ;;
        esac
    done
}

main
