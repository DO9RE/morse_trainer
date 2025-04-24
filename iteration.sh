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
    local unit_length=$(echo "1.2 / $WPM" | bc -l)
    DOT_LENGTH=$unit_length
    DASH_LENGTH=$(echo "$unit_length * 3" | bc -l)
    PAUSE_SYMBOL=$(echo "$unit_length * 1" | bc -l)
    PAUSE_LETTER=$(echo "$unit_length * 3" | bc -l)
    PAUSE_WORD=$(echo "$unit_length * 7" | bc -l)
}

play_morse_tone() {
    local tone_freq=800
    for ((i=0; i<${#1}; i++)); do
        char="${1:$i:1}"
        if [[ "$char" == "." ]]; then
            AUDIODEV=hw:0 play -n synth "$DOT_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        elif [[ "$char" == "-" ]]; then
            AUDIODEV=hw:0 play -n synth "$DASH_LENGTH" sine "$tone_freq" > /dev/null 2>&1
        fi
        sleep "$PAUSE_SYMBOL"
    done
    sleep "$PAUSE_LETTER"
}

log_incorrect_character() {
    local expected="$1"
    local input="$2"

    if [[ ! -f "$ERROR_LOG_FILE" ]]; then
        touch "$ERROR_LOG_FILE"
    fi

    if [[ "$expected" != "$input" ]]; then
        if grep -q "^$expected " "$ERROR_LOG_FILE"; then
            local current_count=$(grep "^$expected " "$ERROR_LOG_FILE" | awk '{print $2}')
            local new_count=$((current_count + 1))
            sed -i "s/^$expected .*/$expected $new_count/" "$ERROR_LOG_FILE"
        else
            echo "$expected 1" >> "$ERROR_LOG_FILE"
        fi
    fi
}

generate_five_groups() {
    local -n group_chars=$1
    local group_count=$2
    local groups=()

    for ((g=0; g<group_count; g++)); do
        local group=""
        for ((i=0; i<5; i++)); do
            group+="${group_chars[RANDOM % ${#group_chars[@]}]}"
        done
        groups+=("$group")
    done

    echo "${groups[@]}"
}

play_and_evaluate_groups() {
    local groups=("$@")
    echo "Listen to the groups and type them. Divide groups with spaces."

    # Intro VVV
    for _ in {1..3}; do
        play_morse_tone "${MORSE_CODE[V]}"
    done

    # Wiedergabe der Gruppen
    (
        for group in "${groups[@]}"; do
            for char in $(echo "$group" | grep -o .); do
                play_morse_tone "${MORSE_CODE[$char]}"
            done
            sleep "$PAUSE_WORD"
        done
        play_morse_tone "${MORSE_CODE[AR]}"
    ) &

    # Benutzereingabe abholen
    read -r -p "Type the groups separated by spaces: " input
    wait

    # Eingabe in Großbuchstaben umwandeln
    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')
    local input_groups=($input) # Benutzergruppen in ein Array umwandeln

    # Gruppenweise Auswertung
    for ((i=0; i<${#groups[@]}; i++)); do
        local expected_group="${groups[i]}"
        local input_group="${input_groups[i]:-}" # Falls keine Eingabe vorhanden, wird ein leerer String verwendet

        if [[ "$expected_group" == "$input_group" ]]; then
            echo "Group $((i+1)): Correct (${expected_group})"
        else
            echo "Group $((i+1)): Wrong (Expected: ${expected_group}, Entered: ${input_group})"

            # Zeichenweiser Vergleich der falschen Gruppe
            for ((j=0; j<${#expected_group}; j++)); do
                local expected_char="${expected_group:j:1}"
                local input_char="${input_group:j:1}"

                if [[ "$expected_char" != "$input_char" ]]; then
                    echo "Character '${expected_char}' was incorrect (Entered: '${input_char:-[none]}')"
                    log_incorrect_character "$expected_char" "$input_char" # Fehlerprotokollierung
                fi
            done
        fi
    done
}

training_mode() {
    echo "Listen carefully: Learn the Morse signs of the current lesson."
    echo "Press Enter to move to the next character. Press Spacebar to repeat the current character."

    local available_chars=("${!MORSE_CODE[@]}")
    available_chars=("${available_chars[@]:0:$LESSON}")

    for char in "${available_chars[@]}"; do
        echo "Character: $char - Morse: ${MORSE_CODE[$char]}"

        while true; do
            # Play the current character
            play_morse_tone "${MORSE_CODE[$char]}"

            # Wait for user input
            echo -n "Press a key: "
            stty -echo -icanon time 0 min 1
            key=$(dd bs=1 count=1 2>/dev/null)
            stty echo icanon

            if [[ -z "$key" ]]; then
                # Enter key moves to the next character
                break
            elif [[ "$key" == " " ]]; then
                # Spacebar repeats the current character
                echo "Repeating character: $char"
                play_morse_tone "${MORSE_CODE[$char]}"
            else
                # Invalid key press
                echo "Invalid input. Press Enter to move to the next character or Spacebar to repeat."
            fi
        done
    done
    echo "Finished listening."
}

train_difficult_characters() {
    echo "Training for difficult characters starts..."
    if [[ ! -f "$ERROR_LOG_FILE" ]]; then
        echo "No error statistics found. Train regular characters."
        return
    fi

    local difficult_chars=()
    while read -r line; do
        local char=$(echo "$line" | awk '{print $1}')
        difficult_chars+=("$char")
    done < <(sort -k2 -n -r "$ERROR_LOG_FILE")

    local groups=($(generate_five_groups difficult_chars 10))
    play_and_evaluate_groups "${groups[@]}"
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
        *) echo "Invalid entry, using standard speed of 20 WPM." ;;
    esac

    echo "Speed changed to $WPM WPM."
    calculate_timings
}

main() {
    load_progress
    calculate_timings

    while true; do
        echo "Welcome to Morse Trainer!"
        echo "1. Listening unit (Learn characters)"
        echo "2. Start typing lesson"
        echo "3. Change speed (current: $WPM WPM)"
        echo "4. Train difficult characters"
        echo "5. Quit"
        read -r -p "Choose an option (1-5): " option

        case $option in
            1)
                training_mode
                ;;
            2)
                local available_chars=("${!MORSE_CODE[@]}")
                available_chars=("${available_chars[@]:0:$LESSON}")
                local groups=($(generate_five_groups available_chars 10))
                play_and_evaluate_groups "${groups[@]}"
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
