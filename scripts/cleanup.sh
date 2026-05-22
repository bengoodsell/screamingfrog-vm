#!/bin/bash
# Clean up old Screaming Frog crawl data in ProjectInstanceData.
#
# Retention is frequency-aware. All crawl data is durably backed up to
# gs://bqdl-uploads/screamingfrog/ and ingested into the screamingfrog.*_pub
# BigQuery tables, so ProjectInstanceData is only a local cache for re-opening
# crawls in the SF GUI. Daily crawls regenerate fast and are kept briefly;
# weekly crawls are kept 2-3 cycles so SF's GUI crawl-comparison still works.
PROJECT_DATA="/home/reporting/.ScreamingFrogSEOSpider/ProjectInstanceData"

# Retention in days, matched by case-insensitive substring of the crawl URL.
# First match wins; anything unmatched gets DEFAULT_DAYS.
# Format: "url-substring:days"
RETENTION_RULES=(
    "bigbrandtire.com:7"   # BBT      - daily
    "jeswork.com:7"        # JESwork  - daily (Groundworks brand)
    "groundworks.com:18"   # GW       - weekly multi-brand, kept longer
)
DEFAULT_DAYS=14            # all other (weekly/monthly) crawls

[ -d "$PROJECT_DATA" ] || exit 0
cd "$PROJECT_DATA" || exit 1

for dir in "$PROJECT_DATA"/*/; do
    [ -d "$dir" ] || continue

    key_file="${dir}DbSeoSpiderFileKey"
    [ -f "$key_file" ] || continue

    url=$(grep -m1 '^url=' "$key_file" | cut -d= -f2-)

    retention=$DEFAULT_DAYS
    for rule in "${RETENTION_RULES[@]}"; do
        pattern="${rule%%:*}"
        days="${rule##*:}"
        if echo "$url" | grep -qiF "$pattern"; then
            retention=$days
            break
        fi
    done

    # Delete the crawl dir if older than its retention period
    find "$dir" -maxdepth 0 -type d -mtime +"$retention" -exec rm -rf {} \;
done
