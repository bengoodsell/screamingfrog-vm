#!/bin/bash
# Delete old crawls based on retention policy
CRAWL_DIR="/home/reporting/crawls"

# Groundworks: 21 days retention
find "$CRAWL_DIR/groundworks" -mindepth 1 -maxdepth 1 -type d -mtime +21 -exec rm -rf {} \;

# All other clients: 14 days retention
for dir in "$CRAWL_DIR"/*/; do
    client=$(basename "$dir")
    [ "$client" = "groundworks" ] && continue
    find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} \;
done
