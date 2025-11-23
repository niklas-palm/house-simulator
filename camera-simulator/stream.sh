#!/bin/bash
set -e

# Environment variables (set by ECS task definition + get-credentials.sh)
# STREAM_NAME - KVS stream name
# AWS_DEFAULT_REGION - AWS region
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN - Set by get-credentials.sh

# Validate required environment variables
if [ -z "$STREAM_NAME" ]; then
    echo "ERROR: STREAM_NAME environment variable is not set"
    exit 1
fi

if [ -z "$AWS_DEFAULT_REGION" ]; then
    echo "ERROR: AWS_DEFAULT_REGION environment variable is not set"
    exit 1
fi

# Verify credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERROR: AWS credentials not set. get-credentials.sh may have failed."
    exit 1
fi

# Default video file location
VIDEO_FILE="${VIDEO_FILE:-/app/video.mp4}"

# Restart interval (4 minutes = 240 seconds, before 5-minute connection degradation)
RESTART_INTERVAL="${RESTART_INTERVAL:-240}"

echo "====================================="
echo "KVS Camera Simulator (GStreamer)"
echo "====================================="
echo "Stream: ${STREAM_NAME}"
echo "Region: ${AWS_DEFAULT_REGION}"
echo "Video: ${VIDEO_FILE}"
echo "Restart Interval: ${RESTART_INTERVAL}s"
echo "====================================="

# Verify video file exists
if [ ! -f "${VIDEO_FILE}" ]; then
    echo "ERROR: Video file not found: ${VIDEO_FILE}"
    exit 1
fi

FILE_SIZE=$(stat -c%s "${VIDEO_FILE}")
echo "Video file ready (${FILE_SIZE} bytes)"

# Verify video properties
echo "Checking video properties..."
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate \
    -of default=noprint_wrappers=1 "${VIDEO_FILE}" 2>&1 | grep -E "codec_name|width|height|r_frame_rate|bit_rate" || true

# Check if kvssink plugin is available
echo "Verifying kvssink plugin..."
if ! gst-inspect-1.0 kvssink > /dev/null 2>&1; then
    echo "ERROR: kvssink plugin not found. Make sure Producer SDK is properly built."
    exit 1
fi
echo "✓ kvssink plugin available"

# Set GST plugin path (adjust if needed based on your build)
export GST_PLUGIN_PATH=/app/amazon-kinesis-video-streams-producer-sdk-cpp/build:${GST_PLUGIN_PATH}

# Set KVS SDK log level (default: INFO, options: VERBOSE, DEBUG, INFO, WARN, ERROR, FATAL, SILENT)
export AWS_KVS_LOG_LEVEL="${AWS_KVS_LOG_LEVEL:-WARN}"
echo "KVS SDK log level: ${AWS_KVS_LOG_LEVEL}"

# Function to stream video with GStreamer
stream_video() {
    echo "[$(date)] Starting GStreamer pipeline..."

    # Use timeout to enforce restart interval
    timeout ${RESTART_INTERVAL}s gst-launch-1.0 -e \
        filesrc location="${VIDEO_FILE}" ! \
        qtdemux ! \
        queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! \
        h264parse ! \
        video/x-h264,stream-format=avc,alignment=au ! \
        kvssink \
            stream-name="${STREAM_NAME}" \
            storage-size=128 \
            access-key="${AWS_ACCESS_KEY_ID}" \
            secret-key="${AWS_SECRET_ACCESS_KEY}" \
            aws-region="${AWS_DEFAULT_REGION}" \
            ${AWS_SESSION_TOKEN:+session-token="${AWS_SESSION_TOKEN}"} \
            log-level="${AWS_KVS_LOG_LEVEL}" \
            framerate=30 \
            || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "[$(date)] ✓ Planned restart after ${RESTART_INTERVAL}s (prevents connection degradation)"
            return 0
        elif [ $EXIT_CODE -eq 130 ]; then
            echo "[$(date)] Stream interrupted by signal"
            return 1
        else
            echo "[$(date)] ⚠ Stream exited unexpectedly with code: $EXIT_CODE"
            return $EXIT_CODE
        fi
    }
}

# Function to handle cleanup
cleanup() {
    echo ""
    echo "[$(date)] Shutting down streaming application..."
    pkill -f gst-launch-1.0 || true
    sleep 1
    echo "[$(date)] Cleanup complete"
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGTERM SIGINT EXIT

# Stream counter for monitoring
STREAM_COUNT=0
FAILURE_COUNT=0
MAX_CONSECUTIVE_FAILURES=5

echo "====================================="
echo "Starting continuous streaming loop"
echo "Restart interval: ${RESTART_INTERVAL}s"
echo "====================================="

# Main streaming loop
while true; do
    STREAM_COUNT=$((STREAM_COUNT + 1))

    echo ""
    echo "=========================================="
    echo "[$(date)] Stream cycle #${STREAM_COUNT}"
    echo "=========================================="

    # Refresh credentials if they're about to expire
    # (get-credentials.sh should be re-run by your orchestration if needed)
    if [ -n "$AWS_SESSION_TOKEN" ]; then
        echo "[$(date)] Using temporary credentials (session token present)"
    fi

    # Stream video
    if stream_video; then
        # Successful cycle
        FAILURE_COUNT=0
        echo "[$(date)] Cycle completed successfully"
    else
        # Failed cycle
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[$(date)] ⚠ Cycle failed (consecutive failures: ${FAILURE_COUNT}/${MAX_CONSECUTIVE_FAILURES})"

        # Exit if too many consecutive failures
        if [ $FAILURE_COUNT -ge $MAX_CONSECUTIVE_FAILURES ]; then
            echo ""
            echo "=========================================="
            echo "ERROR: Too many consecutive failures (${FAILURE_COUNT})"
            echo "Exiting to allow container restart"
            echo "=========================================="
            exit 1
        fi
    fi

    # Cool down period between cycles
    COOLDOWN=2
    echo "[$(date)] Cooling down for ${COOLDOWN}s before next cycle..."
    sleep $COOLDOWN
done
