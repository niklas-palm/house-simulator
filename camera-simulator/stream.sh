#!/bin/bash
set -e

# Environment variables (set by ECS task definition)
# STREAM_NAME - KVS stream name
# AWS_REGION - AWS region (note: IAM role will provide credentials)

# Validate required environment variables
if [ -z "$STREAM_NAME" ]; then
    echo "ERROR: STREAM_NAME environment variable is not set"
    exit 1
fi

if [ -z "$AWS_DEFAULT_REGION" ]; then
    echo "ERROR: AWS_DEFAULT_REGION environment variable is not set"
    exit 1
fi

# Default video file location
VIDEO_FILE="${VIDEO_FILE:-/app/video.mp4}"

echo "====================================="
echo "KVS Camera Simulator"
echo "====================================="
echo "Stream: ${STREAM_NAME}"
echo "Region: ${AWS_DEFAULT_REGION}"
echo "Video: ${VIDEO_FILE}"
echo "====================================="

# Verify video file exists (downloaded at build time)
if [ ! -f "${VIDEO_FILE}" ]; then
    echo "ERROR: Video file not found: ${VIDEO_FILE}"
    exit 1
fi

FILE_SIZE=$(stat -c%s "${VIDEO_FILE}")
echo "Video file ready (${FILE_SIZE} bytes)"

# Function to handle cleanup
cleanup() {
    echo "Stopping the streaming application..."
    pkill -f kvs_gstreamer_sample
    exit
}

# Ensure cleanup is called on exit
trap cleanup EXIT

# Navigate to build directory
cd /app/amazon-kinesis-video-streams-producer-sdk-cpp/build

# Continuous streaming loop
echo "Starting continuous streaming loop..."
while true; do
    echo "[$(date)] Starting stream $STREAM_NAME with file $VIDEO_FILE"
    ./kvs_gstreamer_sample $STREAM_NAME $VIDEO_FILE
    echo "[$(date)] Stream ended. Restarting in 5 seconds..."
    sleep 5
done
