#!/usr/bin/env bash
trap 'cleanup' INT TERM

cleanup() {
  echo "Cleaning up background processes..."
  pkill -P $$
  echo "Script terminated. All background processes have been stopped."
  exit 1
}

PROGRESS_FILE="morse_progress.txt"
DEFAULT_WPM=20
WPM=$DEFAULT_WPM
ERROR_LOG_FILE="error_statistics.txt"
fifo_file="/tmp/audio_fifo"
sample_rate=44100


declare -A MORSE_CODE=(
  [0]="-----" [1]=".----" [2]="..---" [3]="...--" [4]="....-"
  [5]="....." [6]="-...." [7]="--..." [8]="---.." [9]="----."
  [A]=".-" [B]="-..." [C]="-.-." [D]="-.."
  [E]="." [F]="..-." [G]="--." [H]="...."
  [I]=".." [J]=".---" [K]="-.-" [L]=".-.."
  [M]="--" [N]="-." [O]="---" [P]=".--."
  [Q]="--.-" [R]=".-." [S]="..." [T]="-"
  [U]="..-" [V]="...-" [W]=".--" [X]="-..-"
  [Y]="-.--" [Z]="--.." [AR]=".-.-." ["?"]="..--.."
)

setup_aliases() {
  # Detect operating system
  local platform="$OSTYPE"

  if [[ "$platform" == "darwin"* ]]; then
    # macOS-specific aliases
    alias shuf="gshuf"  # Use GNU shuf from coreutils
    alias sed="gsed"    # Use GNU sed from coreutils
    alias grep="ggrep"  # Use GNU grep from coreutils
    # Ensure necessary GNU tools are installed
    if ! command -v gshuf &> /dev/null; then
      echo "Error: gshuf (GNU shuf) is not installed. Install it with 'brew install coreutils'."
      exit 1
    fi
    if ! command -v gsed &> /dev/null; then
      echo "Error: gsed (GNU sed) is not installed. Install it with 'brew install gnu-sed'."
      exit 1
    fi
    if ! command -v ggrep &> /dev/null; then
      echo "Error: ggrep (GNU grep) is not installed. Install it with 'brew install grep'."
      exit 1
    fi

    echo "Aliases set for macOS: shuf -> gshuf, sed -> gsed, grep -> ggrep"
  else
    # Linux-specific aliases (default tools should work)
    unalias shuf 2> /dev/null || true  # Remove alias if previously set
    unalias sed 2> /dev/null || true
    unalias grep 2> /dev/null || true

    echo "Linux detected. No additional aliases required."
  fi
}

sort_morse_code_advanced() {
  # Access the given array via reference
  local -n morse_array=$1

  # Local arrays for categorizing Morse code characters
  declare -a easy_keys=()
  declare -a medium_keys=()
  declare -a hard_keys=()
  declare -a numbers_keys=()
  declare -a special_keys=()
  declare -A temp_array=() # Associative Array for the sorted keys

  # Categorize keys
  for key in "${!morse_array[@]}"; do
    local code="${morse_array[$key]}"
    local length="${#code}"

    if [[ "$key" =~ [0-9] ]]; then
      numbers_keys+=("$key")
    elif [[ "$key" =~ [A-Z] ]]; then
      if [[ "$code" =~ ^(\.|-)\1*$ ]] || [[ "$length" -le 2 ]]; then
        easy_keys+=("$key")
      elif [[ "$length" -le 3 ]]; then
        medium_keys+=("$key")
      else
        hard_keys+=("$key")
      fi
    else
      special_keys+=("$key")
    fi
  done

  # Concatenate sorted keys for letters
  declare -a letters_keys=()
  letters_keys+=("${easy_keys[@]}")
  local max_length=$(( ${#medium_keys[@]} > ${#hard_keys[@]} ? ${#medium_keys[@]} : ${#hard_keys[@]} ))
  for ((i=0; i<max_length; i++)); do
    [[ $i -lt ${#medium_keys[@]} ]] && letters_keys+=("${medium_keys[$i]}")
    [[ $i -lt ${#hard_keys[@]} ]] && letters_keys+=("${hard_keys[$i]}")
  done

  # Interleave letters, numbers, and special characters
  declare -a sorted_keys=()
  local letters_count=${#letters_keys[@]}
  local numbers_count=${#numbers_keys[@]}
  local specials_count=${#special_keys[@]}
  local letters_index=0
  local numbers_index=0
  local specials_index=0
  local iteration=0

  while (( letters_index < letters_count )); do
    # Add two letters
    sorted_keys+=("${letters_keys[letters_index]}")
    ((letters_index++))
    ((iteration++))
    if (( letters_index < letters_count )); then
      sorted_keys+=("${letters_keys[letters_index]}")
      ((letters_index++))
      ((iteration++))
    fi

    # Add one number if available
    if (( numbers_index < numbers_count )); then
      sorted_keys+=("${numbers_keys[numbers_index]}")
      ((numbers_index++))
      ((iteration++))
    fi

    # Add one special character every 3 iterations if available
    if (( iteration % 3 == 0 && specials_index < specials_count )); then
      sorted_keys+=("${special_keys[specials_index]}")
      ((specials_index++))
    fi
  done

  # Add remaining numbers, if any
  while (( numbers_index < numbers_count )); do
    sorted_keys+=("${numbers_keys[numbers_index]}")
    ((numbers_index++))
  done

  # Add remaining special characters, if any
  while (( specials_index < specials_count )); do
    sorted_keys+=("${special_keys[specials_index]}")
    ((specials_index++))
  done

  # Build up new array, based on sorted keys
  for key in "${sorted_keys[@]}"; do
    if [[ -n "${morse_array[$key]}" ]]; then
      temp_array["$key"]="${morse_array[$key]}"
    else
      echo "WARNING!: Key '$key' doesn't exist in source array!"
    fi
  done

  # Delete original array and rebuild
  for key in "${!morse_array[@]}"; do
    unset "morse_array[$key]"
  done
  for key in "${!temp_array[@]}"; do
    morse_array["$key"]="${temp_array[$key]}"
  done
}

generate_location() {
  local file="countries_and_cities.txt"
  local line=$(shuf -n 1 "$file")
  local country_code=$(echo "$line" | cut -d':' -f1)
  local country_name=$(echo "$line" | cut -d':' -f2)
  local cities=$(echo "$line" | cut -d':' -f3)
  local city=$(echo "$cities" | tr ',' '\n' | shuf -n 1 | tr '[:lower:]' '[:upper:]')
  echo "$country_code:$city"
}

generate_name() {
  local name=$(shuf -n 1 names.txt | tr '[:lower:]' '[:upper:]')
  echo "$name"
}

generate_call_sign() {
  local country_code=$1
  local number=$(( RANDOM % 9 + 1 ))
  local suffix=$(cat /dev/urandom | tr -dc 'A-Z' | fold -w 3 | head -n 1)
  local call_sign="${country_code}${number}${suffix}"
  echo "$call_sign"
}

qso_training_mode() {
  local location=$(generate_location)
  local country_code=$(echo "$location" | cut -d':' -f1)
  local city=$(echo "$location" | cut -d':' -f2)
  local call_sign=$(generate_call_sign "$country_code")
  local name=$(generate_name)
  local message="CQ CQ CQ DE $call_sign $call_sign K
$call_sign DE $country_code TNX FER CALL UR QTH $city $city NAME $name $name HW? K
$country_code DE $call_sign R TNX FER RPRT UR QTH $city NAME $name BK TNX FER QSO 73 GL SK"

# Debug: Original Message
# echo "DEBUG: Original message: $message"

# Split message into groups, divide at spaces
  local groups=()
  while IFS= read -r -d ' ' group; do
    groups+=("$group")
  done < <(echo "$message ")

# echo "DEBUG: Split message into groups: ${groups[*]}"

# Playback groupwise in background
  (
  for group in "${groups[@]}"; do
    for char in $(echo "$group" | grep -o .); do
      play_morse_tone "${MORSE_CODE["$char"]}"
    done
sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_WORD" sine 0 > "$fifo_file"
  done
  play_morse_tone "${MORSE_CODE[AR]}" # End signal
  ) &

# Fetch user input
  read -r -p "Type the message: " input

# Compare input and original message
  input=$(echo "$input" | tr '[:lower:]' '[:upper:]')
  local input_groups=($input) # Turn user input into groups

  local total_characters=0
  local correct_characters=0

  for ((i=0; i<${#groups[@]}; i++)); do
    local expected_group="${groups[i]}"
    local input_group="${input_groups[i]:-}" # Standardwert, falls Eingabe kürzer ist
#   Count total characters
    total_characters=$((total_characters + ${#expected_group}))

    if [[ "$expected_group" == "$input_group" ]]; then
      echo "Group $((i+1)): Correct (${expected_group})"
      correct_characters=$((correct_characters + ${#expected_group}))
    else
      echo "Group $((i+1)): Wrong (Expected: ${expected_group}, Entered: ${input_group})"

#     Compare characcter wise
      for ((j=0; j<${#expected_group}; j++)); do
        local expected_char="${expected_group:j:1}"
        local input_char="${input_group:j:1}"

        if [[ "$expected_char" == "$input_char" ]]; then
          correct_characters=$((correct_characters + 1))
        else
          echo "Character '${expected_char}' was incorrect (Entered: '${input_char:-[none]}')"
          log_incorrect_character "$expected_char" "$input_char" # Fehler loggen
        fi
      done
    fi
  done

# Calculate percentage of correct characters, 90 is enough
  local percentage=$((correct_characters * 100 / total_characters))
  echo "Summary: You got $correct_characters out of $total_characters characters correct ($percentage%)."

  if (( percentage >= 90 )); then
    echo "Congratulations! You passed with $percentage%. Keep up the good work!"
  else
    echo "You scored $percentage%. Keep training to improve."
  fi
}

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
  echo "Progress saved."
}

calculate_timings() {
  local unit_length
  unit_length=$(echo "scale=5; 1.2 / $WPM" | bc -l | tr -d '[:space:]')

  DOT_LENGTH=$(echo "$unit_length" | bc -l | tr -d '[:space:]')
  DASH_LENGTH=$(echo "$unit_length * 3" | bc -l | tr -d '[:space:]')
  PAUSE_SYMBOL=$(echo "$unit_length * 1" | bc -l | tr -d '[:space:]')
  PAUSE_LETTER=$(echo "$unit_length * 3" | bc -l | tr -d '[:space:]')
  PAUSE_WORD=$(echo "$unit_length * 7" | bc -l | tr -d '[:space:]')

# Debug-Ausgaben
# echo "DEBUG: WPM: $WPM"
# echo "DEBUG: Unit Length: $unit_length"
# echo "DEBUG: DOT_LENGTH: $DOT_LENGTH"
# echo "DEBUG: DASH_LENGTH: $DASH_LENGTH"
# echo "DEBUG: PAUSE_SYMBOL: $PAUSE_SYMBOL"
# echo "DEBUG: PAUSE_LETTER: $PAUSE_LETTER"
# echo "DEBUG: PAUSE_WORD: $PAUSE_WORD"
}

play_morse_tone() {
    local tone_freq=800              # Frequenz des Tons

    # Überprüfen, ob die FIFO-Datei existiert
    if [[ ! -p "$fifo_file" ]]; then
        echo "Fehler: FIFO-Datei $fifo_file existiert nicht. Bitte initialisiere die Audio-Umgebung."
        return 1
    fi

    # Debug: Morse-Code-Muster anzeigen
#   echo "DEBUG: Spiele Morse-Muster '$1'."

    # Schleife durch das Morse-Muster (z. B. ".-")
    for (( i=0; i<${#1}; i++ )); do
        local char="${1:$i:1}" # Extrahiere das aktuelle Zeichen (Punkt oder Strich)

        case "$char" in
            ".")
                # Punkt (Dot) abspielen
                sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$DOT_LENGTH" sine "$tone_freq" > "$fifo_file"
                ;;
            "-")
                # Strich (Dash) abspielen
                sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$DASH_LENGTH" sine "$tone_freq" > "$fifo_file"
                ;;
            *)
                echo "Ungültiges Zeichen im Morse-Muster: $char"
                ;;
        esac

        # Pause zwischen Symbolen als stille Audiodaten in die FIFO schreiben
        sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_SYMBOL" sine 0 > "$fifo_file"
    done

    # Pause nach dem Buchstaben als stille Audiodaten in die FIFO schreiben
    sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_LETTER" sine 0 > "$fifo_file"
}

play_morse_code() {
  local text="$1"
# echo "DEBUG: Original input text: '$text'"

# Iterate over every character in text
  for (( i=0; i<${#text}; i++ )); do
    local char="${text:i:1}"
    char=$(echo "$char" | tr '[:lower:]' '[:upper:]')
#   echo "DEBUG: Processing character at index $i: '$char'"

#   Tread spaces for word pauses
    if [[ "$char" == " " ]]; then
#     echo "DEBUG: Detected space, pausing for a word."
sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_WORD" sine 0 > "$fifo_file"
      continue
    fi

    if [[ -n "${MORSE_CODE[$char]}" ]]; then
#     echo "DEBUG: Playing Morse code for '$char': ${MORSE_CODE[$char]}"
      play_morse_tone "${MORSE_CODE[$char]}"
    else
      echo "WARNING! No Morse code defined for character '$char'."
    fi

#   Pause between letters
sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_LETTER" sine 0 > "$fifo_file"
  done
# echo "DEBUG: Finished processing text."
}

log_incorrect_character() {
  local expected=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  local input=$(echo "$2" | tr '[:lower:]' '[:upper:]')    # Uppercase-Konvertierung

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
  local total_characters=0
  local correct_characters=0

  echo "Listen to the groups and type them. Divide groups with spaces."

# Intro VVV
  for _ in {1..3}; do
    play_morse_tone "${MORSE_CODE[V]}"
  done

# Play the groups
  ( # happens in background, therefore the parentesis 
  for group in "${groups[@]}"; do
    for char in $(echo "$group" | grep -o .); do
      play_morse_tone "${MORSE_CODE["$char"]}"
    done
sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_WORD" sine 0 > "$fifo_file"
    done
    play_morse_tone "${MORSE_CODE[AR]}"
  ) &

# Get user input
  read -r -p "Type: " input

# Convert input to uppercase
  input=$(echo "$input" | tr '[:lower:]' '[:upper:]')
  local input_groups=($input) # Convert user input into an array

# Evaluate performance
  for ((i=0; i<${#groups[@]}; i++)); do
    local expected_group="${groups[i]}"
    local input_group="${input_groups[i]:-}" # Default to empty if no input provided

#   Count total characters
    total_characters=$((total_characters + ${#expected_group}))

    if [[ "$expected_group" == "$input_group" ]]; then
      echo "Group $((i+1)): Correct (${expected_group})"
      correct_characters=$((correct_characters + ${#expected_group}))
    else
      echo "Group $((i+1)): Wrong (Expected: ${expected_group}, Entered: ${input_group})"

#     Compare character by character
      for ((j=0; j<${#expected_group}; j++)); do
        local expected_char="${expected_group:j:1}"
        local input_char="${input_group:j:1}"

        if [[ "$expected_char" == "$input_char" ]]; then
          correct_characters=$((correct_characters + 1))
        else
          echo "Character '${expected_char}' was incorrect (Entered: '${input_char:-[none]}')"
          log_incorrect_character "$expected_char" "$input_char" # Log errors
        fi
      done
    fi
  done

# Calculate percentage
  local percentage=$((correct_characters * 100 / total_characters))
  echo "Summary: You got $correct_characters out of $total_characters characters correct ($percentage%)."

# Check if the user can advance
  if (( percentage >= 90 )); then
    echo "Congratulations! You passed with $percentage%. Advancing to the next lesson."
    LESSON=$((LESSON + 1))
    save_progress
  else
  echo "You scored $percentage%. Practice more to advance to the next lesson."
  fi
}

training_mode() {
    echo "Listen carefully: Learn the Morse signs of the current lesson."
    echo "Press Enter to move to the next character. Press Spacebar to repeat the current character."

    local available_chars=("${!MORSE_CODE[@]}")
    available_chars=("${available_chars[@]:0:$LESSON}")

    local total_chars=${#available_chars[@]}  # Total number of characters in the lesson

    for (( index=0; index<total_chars; index++ )); do
        local char="${available_chars[index]}"
        echo "Character $((index + 1)) of $total_chars: $char - Morse: ${MORSE_CODE[$char]}"

        # Initial playback of the character
        play_morse_tone "${MORSE_CODE["$char"]}"

        while true; do
            echo -n "Press Enter to advance, or Spacebar to repeat: "
            stty -echo -icanon time 0 min 1
            key=$(dd bs=1 count=1 2>/dev/null)
            stty echo icanon

            if [[ -z "$key" ]]; then
                # Move to the next character
                break
            elif [[ "$key" == " " ]]; then
                # Replay the current character
                echo "Repeating character: $char (Morse: ${MORSE_CODE[$char]})"
                play_morse_tone "${MORSE_CODE[$char]}"
            else
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
    local char=$(echo "$line" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    difficult_chars+=("$char")
  done < <(sort -k2 -n -r "$ERROR_LOG_FILE") # Sortiere nach Fehlerhäufigkeit absteigend

  if [[ ${#difficult_chars[@]} -eq 0 ]]; then
    echo "No difficult characters to train."
    return
  fi

  local groups=($(generate_five_groups difficult_chars 5))

  echo "You will now train your most difficult characters. Listen and type simultaneously!"

  for group in "${groups[@]}"; do
    echo "Training group: $group"

    (
    for char in $(echo "$group" | grep -o .); do
      play_morse_tone "${MORSE_CODE["$char"]}"
    done
sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_WORD" sine 0 > "$fifo_file"
    ) &

    read -r -p "Type the group: " input

    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')

    for ((i=0; i<${#group}; i++)); do
      local expected_char="${group:i:1}"
      local input_char="${input:i:1}"

      if [[ "$expected_char" == "$input_char" ]]; then
        echo "Character '$expected_char': Correct!"
                # Reduce error count in the file
        if grep -q "^$expected_char " "$ERROR_LOG_FILE"; then
          local current_count=$(grep "^$expected_char " "$ERROR_LOG_FILE" | awk '{print $2}')
          local new_count=$((current_count - 1))

          if (( new_count <= 0 )); then
            sed -i "/^$expected_char /d" "$ERROR_LOG_FILE" 
            echo "Character '$expected_char' has been mastered and removed from the error log!"
          else
            sed -i "s/^$expected_char .*/$expected_char $new_count/" "$ERROR_LOG_FILE"
          fi
        fi
      else
        echo "Character '$expected_char': Incorrect (Entered: '${input_char:-[none]}')"
        log_incorrect_character "$expected_char" "$input_char" # Fehler erneut loggen
      fi
    done
  done

  echo "Difficult character training completed."
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

initialize_audio_fifo() {
  local platform="$OSTYPE"
  rm "$fifo_file"
  if ! mkfifo "$fifo_file"; then
    echo "Error: Failed to create FIFO file at $fifo_file."
    return 1
  fi

  if [[ "$platform" == "linux-gnu"* ]]; then
    AUDIODEV=hw:0 play --buffer 1024 -q -t raw -r "$sample_rate" -b 16 -c 1 -e signed-integer "$fifo_file" >/dev/null 2>&1 &
  elif [[ "$platform" == "darwin"* ]]; then
    play --buffer 1024 -q -t raw -r "$sample_rate" -b 16 -c 1 -e signed-integer "$fifo_file" >/dev/null 2>&1 &
  fi

  tail -f /dev/null > "$fifo_file" &
}

morse_input_mode() {
  echo "Select Morse input mode:"
  echo "1. Single key (Up arrow for dots and dashes based on press duration)"
  echo "2. Two keys (Right and Left arrows for dots and dashes)"
  echo "3. Two-key combination (Right+Left for alternating patterns)"
  read -r -p "Choose a mode (1-3): " mode_choice

  case $mode_choice in
    1)
      echo "Single key mode selected. Use the Up arrow key."
      single_key_mode
      ;;
    2)
      echo "Two-key mode selected. Configuring keys..."
      two_key_mode
      ;;
    3)
      echo "Two-key combination mode selected."
      two_key_combination_mode
      ;;
    *)
      echo "Invalid selection. Returning to main menu."
      return
      ;;
  esac
}

play_morse_tone_realtime() {
  local tone_freq=800 # Frequenz des Tons (800 Hz)
  fifo_file_realtime="/tmp/audio_fifo_realtime"

  # FIFO-Datei prüfen/erstellen
  if [[ ! -p "$fifo_file_realtime" ]]; then
    mkfifo "$fifo_file_realtime"
  fi

  # Hintergrundprozess für Rohdatensynthese starten
  (
    sox -n -r $sample_rate -b 16 -c 1 -e signed-integer -t raw - synth 800 sine "$tone_freq" > "$fifo_file_realtime"
  ) &
  tone_pid=$! # Prozess-ID speichern

  AUDIODEV=hw:0 play --buffer 1024 -q -t raw -r "$sample_rate" -b 16 -c 1 -e signed-integer "$fifo_file_realtime" >/dev/null 2>&1 &

  audio_pid=$! # ID des `play`-Prozesses speichern
  tail -f /dev/null > "$fifo_file_realtime" &

}

stop_morse_tone() {
  # Beide Prozesse beenden
  kill "$tone_pid" "$audio_pid" 2>/dev/null
  # FIFO-Datei bereinigen
  rm -f $fifo_file_realtime
}

single_key_mode() {
  echo "Press and hold the Up arrow key to generate Morse code."
  echo "Release the key to stop. Short press for dot, long press for dash."
  echo "Press 'q' to quit."

  while true; do
    read -rsn1 key
    if [[ $key == $'\e' ]]; then
      read -rsn2 key # Read the rest of the escape sequence
      if [[ $key == "[A" ]]; then
        # Begin timing and start tone
        start_time=$(date +%s%N)
        play_morse_tone_realtime

        # Wait until key is released
        while read -rsn1 -t 0.1 key; do
          if [[ -z $key ]]; then
            break
          fi
        done

        # Stop tone and calculate duration
        stop_morse_tone
        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 )) # Duration in ms

        # Determine if it was a dot or dash
        if (( duration < 500 )); then
          echo -n "."
        else
          echo -n "-"
        fi
      fi
    elif [[ $key == "q" ]]; then
      echo "Exiting single key mode."
      break
    fi
  done
}

two_key_mode() {
  echo "Press Right arrow for dots and Left arrow for dashes. Hold for repeated symbols."
  echo "Press 'q' to quit."

  while true; do
    read -rsn1 key
    if [[ $key == $'\e' ]]; then
      read -rsn2 key # Read the rest of the escape sequence
      if [[ $key == "[C" ]]; then
        play_morse_tone_realtime
        echo -n "."
        while read -rsn1 -t 0.1 key; do
          if [[ -z $key ]]; then
            break
          fi
        done
        stop_morse_tone
      elif [[ $key == "[D" ]]; then
        play_morse_tone_realtime
        echo -n "-"
        while read -rsn1 -t 0.1 key; do
          if [[ -z $key ]]; then
            break
          fi
        done
        stop_morse_tone
      fi
    elif [[ $key == "q" ]]; then
      echo "Exiting two-key mode."
      break
    fi
  done
}

two_key_combination_mode() {
  echo "Press and hold Right and Left arrows for alternating dots and dashes."
  echo "Press 'q' to quit."

  while true; do
    read -rsn1 key1
    if [[ $key1 == $'\e' ]]; then
      read -rsn2 key1 # Read the rest of the escape sequence
      if [[ $key1 == "[C" ]]; then
        # Wait for second key press
        read -rsn1 -t 0.5 key2
        if [[ $key2 == $'\e' ]]; then
          read -rsn2 key2
          if [[ $key2 == "[D" ]]; then
            echo "Alternating dots and dashes."
            while true; do
              play_morse_tone_realtime
              echo -n "."
              sleep 0.2
              stop_morse_tone
              play_morse_tone_realtime
              echo -n "-"
              sleep 0.2
              stop_morse_tone
              read -rsn1 -t 0.1 key
              if [[ $key == "q" ]]; then
                break
              fi
            done
          fi
        fi
      elif [[ $key1 == "[D" ]]; then
        # Wait for second key press
        read -rsn1 -t 0.5 key2
        if [[ $key2 == $'\e' ]]; then
          read -rsn2 key2
          if [[ $key2 == "[C" ]]; then
            echo "Alternating dashes and dots."
            while true; do
              play_morse_tone_realtime
              echo -n "-"
              sleep 0.2
              stop_morse_tone
              play_morse_tone_realtime
              echo -n "."
              sleep 0.2
              stop_morse_tone
              read -rsn1 -t 0.1 key
              if [[ $key == "q" ]]; then
                break
              fi
            done
          fi
        fi
      fi
    elif [[ $key1 == "q" ]]; then
      echo "Exiting two-key combination mode."
      break
    fi
  done
}

letters_to_morse_mode() {
  echo "Enter text to convert to Morse code. Press Enter when finished:"
  read -r input_text

  # Convert to uppercase
  input_text=$(echo "$input_text" | tr '[:lower:]' '[:upper:]')

  echo "Morse code:"
  for (( i=0; i<${#input_text}; i++ )); do
    local char="${input_text:i:1}" # Extrahiere das aktuelle Zeichen
    if [[ "$char" == " " ]]; then
      echo -n " / "  # Trennung zwischen Wörtern in der Anzeige
      # Pause zwischen Wörtern in der Audioausgabe
      sox -n -r "$sample_rate" -b 16 -c 1 -e signed-integer -t raw - synth "$PAUSE_WORD" sine 0 > "$fifo_file"
    elif [[ -n "${MORSE_CODE[$char]}" ]]; then
      echo -n "${MORSE_CODE[$char]} "  # Morse-Code für das Zeichen anzeigen
      # Morse-Code für das Zeichen abspielen
      play_morse_tone "${MORSE_CODE[$char]}"
    else
      echo -n "[?] "  # Platzhalter für nicht definierte Zeichen
      echo "WARNING: No Morse code defined for character '$char'."
    fi
  done

  echo -e "\nMorse code playback complete."
}

main() {
  setup_aliases # Check, if we are running Linux or Mac OS
  load_progress
  calculate_timings
  sort_morse_code_advanced MORSE_CODE
  initialize_audio_fifo

  while true; do
    echo "Welcome to Morse Trainer!"
    echo "1. Listening unit (Learn characters)"
    echo "2. Start typing lesson"
    echo "3. Change speed (current: $WPM WPM)"
    echo "4. Train difficult characters"
    echo "5. QSO training mode"
    echo "6. Morse input mode" 
    echo "7. Letters to Morse mode"  
    echo "8. Quit"
    read -r -p "Choose an option (1-8): " option

    case $option in
      1)
        training_mode
        ;;
      2)
        local available_chars=("${!MORSE_CODE[@]}")
        available_chars=("${available_chars[@]:0:$LESSON}")
        local groups=($(generate_five_groups available_chars 10))
        echo "Listen to the five groups and type what you hear. Separate each group with a space, press enter when finish."
        play_and_evaluate_groups "${groups[@]}"
        ;;
      3)
        speed_menu
        ;;
      4)
        train_difficult_characters
        ;;
      5)
        qso_training_mode
        ;;
      6)
        morse_input_mode
        ;;
    7)
      letters_to_morse_mode 
      ;;
      8)
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
