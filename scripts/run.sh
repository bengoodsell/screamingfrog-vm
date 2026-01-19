#!/bin/bash
# Main orchestration script for Screaming Frog pipeline
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/pipeline.log"

mkdir -p "$SCRIPT_DIR/logs"
echo "$(date): Starting pipeline" >> "$LOG_FILE"

"$SCRIPT_DIR/compress.sh" >> "$LOG_FILE" 2>&1
"$SCRIPT_DIR/upload.sh" >> "$LOG_FILE" 2>&1
"$SCRIPT_DIR/cleanup.sh" >> "$LOG_FILE" 2>&1

echo "$(date): Pipeline complete" >> "$LOG_FILE"
