#!/bin/bash
# Compress all CSVs in crawls folder to gzip
CRAWL_DIR="/home/reporting/crawls"

# Change to accessible directory to avoid find restore directory errors
# when run via sudo from a different user's home directory
cd "$CRAWL_DIR" || exit 1

find "$CRAWL_DIR" -type f -name "*.csv" -exec gzip {} \;
