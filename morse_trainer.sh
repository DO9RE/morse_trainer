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
  declare -A temp_array=() # Assoziatives Array für die sortierten Schlüssel

# Debug: Print original array
# echo "DEBUG: Original keys in MORSE_CODE:"
# for key in "${!morse_array[@]}"; do
#   echo "  Key: $key, Value: ${morse_array[$key]}"
# done

# Categorize keys
  for key in "${!morse_array[@]}"; do
    local code="${morse_array[$key]}"
    local length="${#code}"

#   echo "DEBUG: Processing key '$key' with Morse code '$code'"

    if [[ "$key" =~ [0-9] ]]; then
      numbers_keys+=("$key")
    elif [[ "$key" =~ [A-Z] ]]; then
      if [[ "$code" =~ ^(\.|-)\1*$ ]] || [[ "$length" -le 2 ]]; then
        easy_keys+=("$key")
#       echo "DEBUG: Key '$key' categorized as EASY"
      elif [[ "$length" -le 3 ]]; then
        medium_keys+=("$key")
#       echo "DEBUG: Key '$key' categorized as MEDIUM"
      else
        hard_keys+=("$key")
#       echo "DEBUG: Key '$key' categorized as HARD"
      fi
    else
      special_keys+=("$key")
#     echo "DEBUG: Key '$key' categorized as SPECIAL"
    fi
  done

# concatenate sorted keys
  declare -a sorted_keys=() # Special thanks to Sly
  sorted_keys+=("${easy_keys[@]}")
  local max_length=$(( ${#medium_keys[@]} > ${#hard_keys[@]} ? ${#medium_keys[@]} : ${#hard_keys[@]} ))
  for ((i=0; i<max_length; i++)); do
     [[ $i -lt ${#medium_keys[@]} ]] && sorted_keys+=("${medium_keys[$i]}")
     [[ $i -lt ${#hard_keys[@]} ]] && sorted_keys+=("${hard_keys[$i]}")
  done
  sorted_keys+=("${numbers_keys[@]}")
  sorted_keys+=("${special_keys[@]}")

# Debug: Print sorted keys
# echo "DEBUG: Sorted keys:"
# for key in "${sorted_keys[@]}"; do
#   echo "  Key: $key"
# done

# Build up new array, based on sorted keys
  for key in "${sorted_keys[@]}"; do
    if [[ -n "${morse_array[$key]}" ]]; then
      temp_array["$key"]="${morse_array[$key]}"
    else
      echo "WARNING!: Key '$key' doesn't exist in source array!"
    fi
  done

# Debug: Print new array
# echo "DEBUG: New array before overwriting original:"
# for key in "${!temp_array[@]}"; do
#   echo "  Key: $key, Value: ${temp_array[$key]}"
# done

# Delete original array and rebuild
  for key in "${!morse_array[@]}"; do
    unset "morse_array[$key]"
  done
  for key in "${!temp_array[@]}"; do
    morse_array["$key"]="${temp_array[$key]}"
  done

# Debug: Print final array
# echo "DEBUG: Final state of MORSE_CODE:"
# for key in "${!morse_array[@]}"; do
#   echo "  Key: $key, Value: ${morse_array[$key]}"
# done
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
    echo "6. Quit"
    read -r -p "Choose an option (1-6): " option

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
