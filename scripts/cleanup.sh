#!/bin/bash
# Delete old crawls based on retention policy
CRAWL_DIR="/home/reporting/crawls"
PROJECT_DATA="/home/reporting/.ScreamingFrogSEOSpider/ProjectInstanceData"

# Change to accessible directory to avoid find restore directory errors
cd "$CRAWL_DIR" || exit 1

# Groundworks: 21 days retention (target date-stamped dirs at depth 2)
find "$CRAWL_DIR/groundworks" -mindepth 2 -maxdepth 2 -type d -mtime +21 -exec rm -rf {} \;

# All other clients: 14 days retention (target date-stamped dirs at depth 2)
for dir in "$CRAWL_DIR"/*/; do
    client=$(basename "$dir")
    [ "$client" = "groundworks" ] && continue
    find "$dir" -mindepth 2 -maxdepth 2 -type d -mtime +14 -exec rm -rf {} \;
done

# Clean up Screaming Frog ProjectInstanceData (UUID dirs, 21 days retention)
if [ -d "$PROJECT_DATA" ]; then
    find "$PROJECT_DATA" -mindepth 1 -maxdepth 1 -type d -mtime +21 -exec rm -rf {} \;
fi
