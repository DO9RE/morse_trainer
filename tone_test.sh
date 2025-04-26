#!/bin/bash

# Check if sox is installed
if ! command -v play &> /dev/null; then
    echo "Error: sox is not installed. Install it using 'brew install sox' and try again."
    exit 1
fi

# Short tones with appropriate pauses
echo "Playing short tones for Morse testing..."

# Sine wave tones
play -n synth 0.05 sine 440 vol 0.5
sleep 0.1
play -n synth 0.05 sine 550 vol 0.5
sleep 0.1
play -n synth 0.05 sine 660 vol 0.5
sleep 0.1

# Square wave tones
play -n synth 0.05 square 440 vol 0.5
sleep 0.1
play -n synth 0.05 square 550 vol 0.5
sleep 0.1
play -n synth 0.05 square 660 vol 0.5

echo "Short tone playback completed."
