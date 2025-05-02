#include <AudioToolbox/AudioToolbox.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define BUFFER_SIZE 4096

typedef struct {
    int fd; // File descriptor für die FIFO
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[3];
} PlaybackState;

void AudioQueueCallback(void *userData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    PlaybackState *state = (PlaybackState *)userData;
    ssize_t bytesRead = read(state->fd, inBuffer->mAudioData, BUFFER_SIZE);
    if (bytesRead > 0) {
        inBuffer->mAudioDataByteSize = (UInt32)bytesRead;
        AudioQueueEnqueueBuffer(state->queue, inBuffer, 0, NULL);
    } else {
        // Keine Daten mehr? FIFO wird warten.
        usleep(10000); // 10 ms Pause
        AudioQueueEnqueueBuffer(state->queue, inBuffer, 0, NULL);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <fifo_path>\n", argv[0]);
        return 1;
    }

    const char *fifo_path = argv[1];
    int fd = open(fifo_path, O_RDONLY);
    if (fd < 0) {
        perror("Failed to open FIFO");
        return 1;
    }

    PlaybackState state = {0};
    state.fd = fd;

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 44100.0; // Abtastrate
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 1; // Mono
    format.mBitsPerChannel = 16;
    format.mBytesPerPacket = 2; // 16 Bit * 1 Kanal / 8
    format.mBytesPerFrame = 2;  // 16 Bit * 1 Kanal / 8

    OSStatus status = AudioQueueNewOutput(
        &format,
        AudioQueueCallback,
        &state,
        NULL,
        NULL,
        0,
        &state.queue
    );

    if (status != noErr) {
        fprintf(stderr, "AudioQueueNewOutput failed: %d\n", status);
        close(fd);
        return 1;
    }

    // Vorab ein paar Buffer anlegen
    for (int i = 0; i < 3; i++) {
        AudioQueueAllocateBuffer(state.queue, BUFFER_SIZE, &state.buffers[i]);
        AudioQueueCallback(&state, state.queue, state.buffers[i]);
    }

    AudioQueueStart(state.queue, NULL);

    printf("Listening to FIFO: %s\n", fifo_path);
    printf("Playing RAW PCM 44100Hz, 16bit, Mono\n");

    // Läuft, bis abgebrochen wird
    while (1) {
        sleep(1);
    }

    AudioQueueStop(state.queue, true);
    AudioQueueDispose(state.queue, true);
    close(fd);
    return 0;
}
