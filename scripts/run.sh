#!/bin/bash
# Main orchestration script for Screaming Frog pipeline
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/pipeline.log"

mkdir -p "$SCRIPT_DIR/logs"
echo "$(date): Starting pipeline" >> "$LOG_FILE"

# Compress stage
if ! "$SCRIPT_DIR/compress.sh" >> "$LOG_FILE" 2>&1; then
    echo "$(date): ERROR - Compress failed" >> "$LOG_FILE"
    exit 1
fi

# Upload stage
if ! "$SCRIPT_DIR/upload.sh" >> "$LOG_FILE" 2>&1; then
    echo "$(date): ERROR - Upload failed" >> "$LOG_FILE"
    exit 1
fi

# Cleanup stage (non-fatal)
if ! "$SCRIPT_DIR/cleanup.sh" >> "$LOG_FILE" 2>&1; then
    echo "$(date): WARNING - Cleanup failed" >> "$LOG_FILE"
fi

echo "$(date): Pipeline complete" >> "$LOG_FILE"
