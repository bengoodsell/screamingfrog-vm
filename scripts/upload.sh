#!/bin/bash
# Upload crawls to GCS and delete on success
CRAWL_DIR="/home/reporting/crawls"
GCS_BUCKET="gs://bqdl-uploads/screamingfrog"

# Change to accessible directory to avoid find restore directory errors
cd "$CRAWL_DIR" || exit 1

# Sync each client folder to GCS
for client_dir in "$CRAWL_DIR"/*/; do
    client=$(basename "$client_dir")
    /snap/bin/gcloud storage rsync "$client_dir" "$GCS_BUCKET/$client" --recursive && \
    find "$client_dir" -type f \( -name "*.csv" -o -name "*.gz" \) -delete
done
