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
  [Y]="-.--" [Z]="--.." [AR]=".-.-." ["?"]="..--.."
  [0]="-----" [1]=".----" [2]="..---" [3]="...--" [4]="....-"
  [5]="....." [6]="-...." [7]="--..." [8]="---.." [9]="----."
)

sort_morse_code_advanced() {
  local -n morse_array=$1  # Access the given array as reference
  local easy_keys=() # Signs with easy patterns, E, T ...
  local medium_keys=() # Characters with middel complexity. I, M, S, O ...
  local hard_keys=() 
  local numbers_keys=()
  local special_keys=()
  local sorted_keys=()     # Endgültig sortierte Liste

  for key in "${!morse_array[@]}"; do
    local code="${morse_array[$key]}"
    local length="${#code}"
        
#   Categorize the patterns
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

# Easy keys first
  sorted_keys+=("${easy_keys[@]}")
# Middle and hard characters alternating
  local max_length=$(( ${#medium_keys[@]} > ${#hard_keys[@]} ? ${#medium_keys[@]} : ${#hard_keys[@]} ))
  for ((i=0; i<max_length; i++)); do
    [[ $i -lt ${#medium_keys[@]} ]] && sorted_keys+=("${medium_keys[$i]}")
    [[ $i -lt ${#hard_keys[@]} ]] && sorted_keys+=("${hard_keys[$i]}")
  done

# Numbers and special characters in the end
  sorted_keys+=("${numbers_keys[@]}")
  sorted_keys+=("${special_keys[@]}")

# refresh array with new order
  local temp_array=()
  for key in "${sorted_keys[@]}"; do
    echo "Processing key: $key"  # Debugging
    if [[ "$key" == "?" ]]; then
      temp_array["$key"]="${morse_array['?']}"  # Spezialbehandlung für ?
    else
      temp_array["$key"]="${morse_array["$key"]}"
    fi
  done

# Overwrite original array
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
  local city=$(echo "$cities" | tr ',' '\n' | shuf -n 1)
  echo "$country_code:$city"
}

generate_name() {
  local name=$(shuf -n 1 names.txt)
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
  echo "$message"
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
    sleep "$PAUSE_WORD"
    done
    play_morse_tone "${MORSE_CODE[AR]}"
  ) &

# Get user input
  read -r -p "Type: " input
  wait # Give the background process time to finish

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

    while true; do
      char="${available_chars[index]}"
      echo "Playing character: $char (Morse: ${MORSE_CODE["$char"]})"
      play_morse_tone "${MORSE_CODE["$char"]}"

      echo -n "Press Enter to advance, or Spacebar to repeat: "
      stty -echo -icanon time 0 min 1
      key=$(dd bs=1 count=1 2>/dev/null)
      stty echo icanon

      if [[ -z "$key" ]]; then
        break # Next character
      elif [[ "$key" == " " ]]; then
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
    local char=$(echo "$line" | awk '{print $1}')
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
    sleep "$PAUSE_WORD"
    ) &

    read -r -p "Type the group: " input
    wait 

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

main() {
  load_progress
  calculate_timings
  sort_morse_code_advanced MORSE_CODE

  while true; do
    echo "Welcome to Morse Trainer!"
    echo "1. Listening unit (Learn characters)"
    echo "2. Start typing lesson"
    echo "3. Change speed (current: $WPM WPM)"
    echo "4. Train difficult characters"
    echo "5. QSO training mode"
    echo "6. Quit"
    read -r -p "Choose an option (1-5): " option

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
