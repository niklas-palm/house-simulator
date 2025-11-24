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

echo "====================================="
echo "KVS Camera Simulator (GStreamer)"
echo "====================================="
echo "Stream: ${STREAM_NAME}"
echo "Region: ${AWS_DEFAULT_REGION}"
echo "Video: ${VIDEO_FILE}"
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

# Set KVS SDK log level (default: ERROR, options: VERBOSE, DEBUG, INFO, WARN, ERROR, FATAL, SILENT)
export AWS_KVS_LOG_LEVEL="${AWS_KVS_LOG_LEVEL:-ERROR}"
echo "KVS SDK log level: ${AWS_KVS_LOG_LEVEL}"

# Set GStreamer log level (0=none, 1=ERROR, 2=WARNING, 3=INFO, 4+=DEBUG)
# Setting to 1 (ERROR only) to minimize logging
export GST_DEBUG="${GST_DEBUG:-1}"
echo "GStreamer log level: ${GST_DEBUG}"

# Function to refresh credentials from ECS metadata endpoint
refresh_credentials() {
    echo "[$(date)] Refreshing credentials from ECS metadata endpoint..."

    if [ -z "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
        echo "[$(date)] No ECS metadata endpoint available"
        return 1
    fi

    CREDS=$(curl -s "http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}")

    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['AccessKeyId'])")
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['SecretAccessKey'])")
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Token'])")

    echo "[$(date)] Credentials refreshed successfully"
    return 0
}

# Function to stream video with GStreamer
stream_video() {
    echo "[$(date)] Starting GStreamer pipeline..."

    # Capture output to check for credential expiration
    OUTPUT_FILE=$(mktemp)

    gst-launch-1.0 -e \
        filesrc location="${VIDEO_FILE}" ! \
        qtdemux ! \
        h264parse ! \
        video/x-h264,stream-format=avc,alignment=au ! \
        identity sync=true ! \
        kvssink \
            stream-name="${STREAM_NAME}" \
            storage-size=512 \
            access-key="${AWS_ACCESS_KEY_ID}" \
            secret-key="${AWS_SECRET_ACCESS_KEY}" \
            aws-region="${AWS_DEFAULT_REGION}" \
            ${AWS_SESSION_TOKEN:+session-token="${AWS_SESSION_TOKEN}"} \
        2>&1 | tee "$OUTPUT_FILE"

    EXIT_CODE=$?

    # Check for expired credentials
    if grep -q "security token included in the request is expired" "$OUTPUT_FILE"; then
        echo "[$(date)] ⚠ Credentials expired, need to refresh"
        rm -f "$OUTPUT_FILE"
        return 2  # Special code for credential expiration
    fi

    rm -f "$OUTPUT_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "[$(date)] Video finished, looping..."
        return 0
    elif [ $EXIT_CODE -eq 130 ]; then
        echo "[$(date)] Stream interrupted by signal"
        return 1
    else
        echo "[$(date)] ⚠ Stream exited with code: $EXIT_CODE"
        return $EXIT_CODE
    fi
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

echo "====================================="
echo "Starting continuous streaming loop"
echo "Video will loop automatically"
echo "====================================="

# Main streaming loop
while true; do
    STREAM_COUNT=$((STREAM_COUNT + 1))

    echo ""
    echo "=========================================="
    echo "[$(date)] Stream loop #${STREAM_COUNT}"
    echo "=========================================="

    # Stream video
    stream_video
    RESULT=$?

    if [ $RESULT -eq 2 ]; then
        # Credentials expired, refresh and retry immediately
        echo "[$(date)] Refreshing credentials and restarting stream..."
        if refresh_credentials; then
            echo "[$(date)] Retrying with fresh credentials..."
            sleep 2
        else
            echo "[$(date)] Failed to refresh credentials, retrying in 30 seconds..."
            sleep 30
        fi
    elif [ $RESULT -ne 0 ]; then
        echo "[$(date)] Stream failed, retrying in 5 seconds..."
        sleep 5
    fi
done
