#!/bin/bash
# Clean up old Screaming Frog internal data
PROJECT_DATA="/home/reporting/.ScreamingFrogSEOSpider/ProjectInstanceData"

if [ -d "$PROJECT_DATA" ]; then
    cd "$PROJECT_DATA" || exit 1
    find "$PROJECT_DATA" -mindepth 1 -maxdepth 1 -type d -mtime +21 -exec rm -rf {} \;
fi
