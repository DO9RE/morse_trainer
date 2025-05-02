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

# Function to generate sine waves with SoX
generate_wave() {
    local duration=$1
    local frequency=$2
    sox -n -r 44100 -c 2 -b 16 -t raw - synth "$duration" sine "$frequency" > "$FIFO_PATH"
}

# Read user input and send audio data
while read -r -n1 char; do
    case $char in
        ".")
            # Dot: Short sine wave (440 Hz for 0.1 seconds)
            generate_wave 0.1 440
            ;;
        "-")
            # Dash: Long sine wave (440 Hz for 0.3 seconds)
            generate_wave 0.3 440
            ;;
        *)
            echo "Invalid input. Enter only dots (.) or dashes (-)."
            ;;
    esac
done

# Clean up when done
cleanup
