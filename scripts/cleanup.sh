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
    "groundworks.com:18"   # GW       - weekly multi-brand, kept longer
)
# JESwork's standalone daily task was retired 2026-06-29 (CF block resolved
# 6/22, GW comprehensive now covers jeswork.com). Rule removed; jeswork.com is
# now crawled only as part of groundworks.com, which already gets 18 days.
DEFAULT_DAYS=14            # all other (weekly/monthly) crawls

# --- Guard: never delete a crawl that is currently running -------------------
# SF updates files INSIDE a project dir but does not add/remove entries at the
# top level, so the directory's own mtime stays frozen at creation time. A crawl
# running for longer than its retention window therefore looks "old" to
# find -mtime and would be rm -rf'd mid-flight. Age is not a safe proxy for
# "finished" - guard on actual use instead.
# (Found 2026-08-31: a 10-day-old Audible crawl was 3 days from being deleted
# while still running.)
is_in_use() {
    local uuid="$1" pid
    for pid in $(pgrep -f 'ScreamingFrogSEOSpider.jar' 2>/dev/null); do
        if ls -l "/proc/$pid/fd" 2>/dev/null | grep -q "$uuid"; then
            return 0
        fi
    done
    return 1
}

[ -d "$PROJECT_DATA" ] || exit 0
cd "$PROJECT_DATA" || exit 1

for dir in "$PROJECT_DATA"/*/; do
    [ -d "$dir" ] || continue

    key_file="${dir}DbSeoSpiderFileKey"
    [ -f "$key_file" ] || continue

    url=$(grep -m1 '^url=' "$key_file" | cut -d= -f2-)

    # Skip crawls that are still running - see is_in_use() above.
    uuid=$(basename "$dir")
    if is_in_use "$uuid"; then
        echo "cleanup: SKIP (crawl in progress) $uuid  $url"
        continue
    fi

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
