#!/bin/bash
# Compress all CSVs in crawls folder to gzip
CRAWL_DIR="/home/reporting/crawls"
find "$CRAWL_DIR" -type f -name "*.csv" -exec gzip {} \;
