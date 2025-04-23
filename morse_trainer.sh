#!/bin/bash

PROGRESS_FILE="morse_progress.txt"
DEFAULT_WPM=20
WPM=$DEFAULT_WPM
ERROR_LOG_FILE="error_statistics.txt"

declare -A MORSE_CODE=(
    [A]=".-" [B]="-..." [C]="-.-." [D]="-.."
    [E]="." [F]="..-." [G]="--." [H]="...."
    [I]=".." [J]=".---" [K]="-.-" [L]=".-.."
    [M]="--" [N]="-." [O]="---" [P]=".--."
    [Q]="--.-" [R]=".-." [S]="..." [T]="-"
    [U]="..-" [V]="...-" [W]=".--" [X]="-..-"
    [Y]="-.--" [Z]="--.." [AR]=".-.-."
)

load_progress() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        LESSON=$(<"$PROGRESS_FILE")
    else
        LESSON=2
        echo "$LESSON" > "$PROGRESS_FILE"
    fi
}

save_progress() {
    echo "$LESSON" > "$PROGRESS_FILE"
}

calculate_timings() {
    local unit_length=$(echo "1.2 / $WPM" | bc -l)  # Unit for a dot in seconds
    DOT_LENGTH=$unit_length
    DASH_LENGTH=$(echo "$unit_length * 3" | bc -l)
    PAUSE_SYMBOL=$(echo "$unit_length * 1" | bc -l)
    PAUSE_LETTER=$(echo "$unit_length * 3" | bc -l)
    PAUSE_WORD=$(echo "$unit_length * 7" | bc -l)

    # How many 5groups according to speed?
    case $WPM in
        5) GROUP_COUNT=10 ;;
        10) GROUP_COUNT=12 ;;
        15) GROUP_COUNT=15 ;;
        20) GROUP_COUNT=17 ;;
        25) GROUP_COUNT=18 ;;
        30) GROUP_COUNT=20 ;;
        *) GROUP_COUNT=10 ;;
    esac
}

# Tone generator function
play_morse_tone() {
    local tone_freq=800 

    for (( i=0; i<${#1}; i++ )); do
        char="${1:$i:1}"
        if [[ "$char" == "." ]]; then
            AUDIODEV=hw:0 play -n synth "$DOT_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        elif [[ "$char" == "-" ]]; then
            AUDIODEV=hw:0 play -n synth "$DASH_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        fi
        sleep "$PAUSE_SYMBOL"
    done
    sleep "$PAUSE_LETTER"  # Pause between letters
}

# Funktion zur Überprüfung der Eingabe und Protokollierung von Fehlern
check_and_log_input() {
    local expected="$1"
    local input="$2"

    # Erstelle die Datei, falls sie nicht existiert
    if [[ ! -f "$ERROR_LOG_FILE" ]]; then
        touch "$ERROR_LOG_FILE"
    fi

    if [[ "$expected" == "$input" ]]; then
        echo "Korrekt!"
        return 0
    else
        echo "Falsch! Erwartet: $expected, Eingegeben: $input"
        
        # Aktualisiere die Fehlerstatistik
        if grep -q "^$expected " "$ERROR_LOG_FILE"; then
            sed -i "s/^$expected \([0-9]*\)$/echo "$expected $((\1 + 1))"/e" "$ERROR_LOG_FILE"
        else
            echo "$expected 1" >> "$ERROR_LOG_FILE"
        fi
        return 1
    fi
}

# Training für schwierige Zeichen
train_difficult_characters() {
    echo "Training für schwierige Zeichen beginnt..."
    
    if [[ ! -f "$ERROR_LOG_FILE" ]]; then
        echo "Keine Fehlerstatistik verfügbar. Üben Sie reguläre Zeichen."
        return
    fi

    # Sortiere nach Fehleranzahl und frage die Zeichen ab
    while read -r line; do
        local char=$(echo "$line" | awk '{print $1}')
        local count=$(echo "$line" | awk '{print $2}')
        echo "Übe das Zeichen '$char' (Fehleranzahl: $count)"
        play_morse_tone "${MORSE_CODE[$char]}"
        read -r -p "Gib das Zeichen ein: " input
        check_and_log_input "$char" "$input"
    done < <(sort -k2 -n -r "$ERROR_LOG_FILE")
}

# Listen to letters
training_mode() {
    echo "Listen carefully: Learn the Morse sigens of the current lection."
    echo "Press Enter to advance to the next sign."
    
    # Select sign for current lesson
    local available_chars=("${!MORSE_CODE[@]}")
    available_chars=("${available_chars[@]:0:$LESSON}")

    for char in "${available_chars[@]}"; do
        echo "Sign: $char - Morse: ${MORSE_CODE[$char]}"
        play_morse_tone "${MORSE_CODE[$char]}"
        read -r -p "Return to continue..."
    done
    echo "Finished listening."
}

speed_menu() {
    echo "Speed selection:"
    echo "1. 5 WPM (slow)"
    echo "2. 10 WPM"
    echo "3. 15 WPM"
    echo "4. 20 WPM (Standard)"
    echo "5. 25 WPM"
    echo "6. 30 WPM (fast)"
    read -r -p "Speed (1-6): " speed_choice

    case $speed_choice in
        1) WPM=5 ;;
        2) WPM=10 ;;
        3) WPM=15 ;;
        4) WPM=20 ;;
        5) WPM=25 ;;
        6) WPM=30 ;;
        *) echo "Invalid entry, use standard speed of 20 WPM." ;;
    esac

    echo "Speed changed to $WPM WPM."
    calculate_timings
}

# Main program
main() {
    load_progress
    calculate_timings

    while true; do
        echo "Welcome to Morse Trainer!"
        echo "1. Listening unit. (Learn signs)"
        echo "2. Start typing lesson"
        echo "3. Change speed (current: $WPM WPM)"
        echo "4. Training für schwierige Zeichen"
        echo "5. Quit"
        read -r -p "Chose an option (1-5): " option

        case $option in
            1)
                training_mode
                ;;
            2)
                echo "Current lesson: $LESSON signs."
                echo "$GROUP_COUNT five groups are played back."

                # Select signs for lesson
                local available_chars=("${!MORSE_CODE[@]}")
                available_chars=("${available_chars[@]:0:$LESSON}")

                # Intro VVV
                for _ in {1..3}; do
                    play_morse_tone "${MORSE_CODE[V]}"
                done

                # Build the 5groups
                local groups=()
                for ((g=0; g<$GROUP_COUNT; g++)); do
                    local group=""
                    for ((i=0; i<5; i++)); do
                        group+="${available_chars[RANDOM % ${#available_chars[@]}]}"
                    done
                    groups+=("$group")
                done

                # Play back and fetch user input
                echo "Listen and type. Divide groups with spaces."
                local input=""
                
                (
                    for group in "${groups[@]}"; do
                        for char in $(echo "$group" | grep -o .); do
                            play_morse_tone "${MORSE_CODE[$char]}"
                        done
                        sleep "$PAUSE_WORD"  # Pause between groups
                    done
                    # End sign "AR"
                    play_morse_tone "${MORSE_CODE[AR]}"
                ) &

                read -r -p "type: " input

                wait

                input=$(echo "$input" | tr '[:lower:]' '[:upper:]')

                # Check every group individually
                local correct_groups=0
                local total_groups=${#groups[@]}
                local input_groups=($input)

                for ((i=0; i<total_groups; i++)); do
                    if [[ "${groups[i]}" == "${input_groups[i]:-}" ]]; then
                        echo "Group $((i+1)): Correkt (${groups[i]})"
                        ((correct_groups++))
                    else
                        echo "Group $((i+1)): Wrong (Correct: ${groups[i]})"
                        check_and_log_input "${groups[i]}" "${input_groups[i]:-}"
                    fi
                done

                local percentage=$((correct_groups * 100 / total_groups))
                echo "Result: $correct_groups/$total_groups Gruppen korrekt ($percentage%)."

                if ((percentage >= 90)); then
                    echo "Congratz, advance to next lesson."
                    ((LESSON++))
                    save_progress
                    break
                else
                    echo "Try again."
                fi
                ;;
            3)
                speed_menu
                ;;
            4)
                train_difficult_characters
                ;;
            5)
                echo "Bye."
                exit 0
                ;;
            *)
                echo "Invalid entry, try again."
                ;;
        esac
    done
}

main
