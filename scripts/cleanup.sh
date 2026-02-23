#!/bin/bash
# Clean up old Screaming Frog internal data with per-client retention
PROJECT_DATA="/home/reporting/.ScreamingFrogSEOSpider/ProjectInstanceData"

# Retention periods (days)
GROUNDWORKS_DAYS=18
DEFAULT_DAYS=14

if [ -d "$PROJECT_DATA" ]; then
    cd "$PROJECT_DATA" || exit 1

    for dir in "$PROJECT_DATA"/*/; do
        [ -d "$dir" ] || continue

        key_file="$dir/DbSeoSpiderFileKey"
        [ -f "$key_file" ] || continue

        # Determine retention based on crawl URL
        url=$(grep '^url=' "$key_file" | head -1 | cut -d= -f2-)
        if echo "$url" | grep -qi 'groundworks'; then
            retention=$GROUNDWORKS_DAYS
        else
            retention=$DEFAULT_DAYS
        fi

        # Delete if directory is older than retention period
        find "$dir" -maxdepth 0 -type d -mtime +$retention -exec rm -rf {} \;
    done
fi
