#!/bin/bash

# Define the FIFO file path
FIFO_PATH="/tmp/morse_fifo"

# Create the FIFO if it doesn't exist
if [[ ! -p $FIFO_PATH ]]; then
    mkfifo $FIFO_PATH
fi

# Start the player in the background
./fifo_audio_player "$FIFO_PATH" &
PLAYER_PID=$!

# Function to clean up on exit
cleanup() {
    echo "Stopping player..."
    kill $PLAYER_PID
    rm -f $FIFO_PATH
    exit
}

# Trap signals to clean up properly
trap cleanup SIGINT SIGTERM

echo "Morse player running. Enter dots (.) and dashes (-) followed by Enter to send signals."
echo "Press Ctrl+C to exit."

# Function to generate sine waves
generate_wave() {
    local duration=$1
    local amplitude=32767
    local frequency=$2
    local sample_rate=44100
    local num_samples=$((duration * sample_rate))

    for ((n = 0; n < num_samples; n++)); do
        sample=$(awk -v n="$n" -v freq="$frequency" -v amp="$amplitude" -v rate="$sample_rate" \
            'BEGIN { print int(amp * sin(2 * 3.14159 * freq * n / rate)) }')
        printf "%04x" $sample | xxd -r -p
        printf "%04x" $sample | xxd -r -p
    done
}

# Read user input and send audio data
while read -r -n1 char; do
    case $char in
        ".")
            # Dot: Short sine wave (e.g., 440 Hz for 0.1 second)
            generate_wave 0.1 440 > "$FIFO_PATH"
            ;;
        "-")
            # Dash: Long sine wave (e.g., 440 Hz for 0.3 second)
            generate_wave 0.3 440 > "$FIFO_PATH"
            ;;
        *)
            echo "Invalid input. Enter only dots (.) or dashes (-)."
            ;;
    esac
done

# Clean up when done
cleanup
