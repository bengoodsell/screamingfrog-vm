# Screaming Frog GCP VM Pipeline

Pipeline scripts for compressing, uploading, and cleaning Screaming Frog crawl exports on GCP VM.

## VM Management

### SSH Access
```bash
# SSH into the VM
/snap/bin/gcloud compute ssh screaming-frog --zone=us-east4-a

# Run command as reporting user
sudo -u reporting <command>

# SSH and run single command
/snap/bin/gcloud compute ssh screaming-frog --zone=us-east4-a --command="<command>"
```

### Chrome Remote Desktop
For GUI access to Screaming Frog scheduled tasks, use Chrome Remote Desktop.

### VM Details
| Property | Value |
|----------|-------|
| VM Name | `screaming-frog` |
| Zone | `us-east4-a` |
| Project | `tight-ship-consulting` |
| SF User | `reporting` |
| gcloud path | `/snap/bin/gcloud` |
| Screaming Frog | `/usr/bin/screamingfrogseospider` (v23.2) |

## Pipeline Scripts

### Directory Structure
```
/home/reporting/
├── crawls/                    # Screaming Frog export location
│   ├── audible/
│   ├── groundworks/
│   └── indagare/
└── screamingfrog-vm/          # This repo (cloned)
    └── scripts/
        ├── compress.sh        # Gzip CSVs
        ├── upload.sh          # Upload to GCS
        ├── cleanup.sh         # Delete old crawls
        ├── run.sh             # Orchestration
        └── logs/              # Pipeline logs
```

### Scripts

#### compress.sh
Compresses all CSV files in the crawls directory to gzip format.
```bash
find /home/reporting/crawls -type f -name "*.csv" -exec gzip {} \;
```

#### upload.sh
Uploads each client folder to GCS and deletes local files on success.
- GCS Bucket: `gs://bqdl-uploads/screamingfrog/`
- Uses `gcloud storage rsync` for efficient uploads

#### cleanup.sh
Deletes old crawl directories based on retention policy:
- **Groundworks**: 21 days
- **All other clients**: 14 days

#### run.sh
Main orchestration script that runs all pipeline steps in sequence.
Logs output to `scripts/logs/pipeline.log`.

### Cron Configuration
Pipeline runs daily at 7 AM via cron (as `reporting` user):
```cron
0 7 * * * /home/reporting/screamingfrog-vm/scripts/run.sh
```

## Full Data Pipeline

```
VM: Screaming Frog exports CSVs
    ↓
scripts/compress.sh → gzip files
    ↓
scripts/upload.sh → gs://bqdl-uploads/screamingfrog/
    ↓
bqdl Cloud Function (Eventarc trigger)
    ↓
BigQuery: screamingfrog.*_raw tables
    ↓
Stored Procedure (every 6 hours)
    ↓
BigQuery: screamingfrog.*_pub tables
```

## Cloud Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `bqdl` | Eventarc (GCS upload) | Import CSVs to BigQuery |
| `monitor-crawl-emails` | Cloud Scheduler (30 min) | Track crawl completion |
| `screamingfrog-raw-to-pub` | Cloud Scheduler (6 hours) | Transform raw → pub |
| `delete-test-crawl` | HTTP | Remove test crawls |

## BigQuery Tables

### Dataset: `screamingfrog`

| Table | Description |
|-------|-------------|
| `internal_raw` / `internal_pub` | Main crawl data |
| `issues_raw` / `issues_pub` | SEO issues |
| `overview_raw` / `overview_pub` | Crawl overview |
| `segments_raw` / `segments_pub` | URL segments |
| `crawl_emails` | Email tracking |
| `pipeline_alerts` | Alert suppression |

## Troubleshooting

### Check Pipeline Logs
```bash
/snap/bin/gcloud compute ssh screaming-frog --zone=us-east4-a --command="cat /home/reporting/screamingfrog-vm/scripts/logs/pipeline.log"
```

### Verify GCS Uploads
```bash
/snap/bin/gcloud storage ls gs://bqdl-uploads/screamingfrog/
```

### Check BigQuery for Recent Data
```sql
SELECT client, crawl_id, COUNT(*) as rows
FROM `tight-ship-consulting.screamingfrog.internal_raw`
WHERE DATE(upload_timestamp) = CURRENT_DATE()
GROUP BY 1, 2
```

### Schema Mismatch Errors
If `bqdl` fails with schema errors, check the CSV columns match the BigQuery table schema.

### Manual Pipeline Run
```bash
/snap/bin/gcloud compute ssh screaming-frog --zone=us-east4-a --command="sudo -u reporting /home/reporting/screamingfrog-vm/scripts/run.sh"
```

### Suppress Pipeline Alerts
```sql
INSERT INTO `tight-ship-consulting.screamingfrog.pipeline_alerts`
(client, suppressed_until, reason)
VALUES ('client_name', TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY), 'Reason');
```

## Related Resources

- **SfAutoUpload (deprecated)**: `/Users/bengoods/SfAutoUpload/`
- **GCS Bucket**: `gs://bqdl-uploads/screamingfrog`
- **GCP Project**: `tight-ship-consulting`

## Updating Scripts

### Local Development
```bash
# Make changes locally, commit, and push
git add . && git commit -m "Update scripts" && git push
```

### Deploy to VM
```bash
/snap/bin/gcloud compute ssh screaming-frog --zone=us-east4-a --command="cd /home/reporting/screamingfrog-vm && sudo -u reporting git pull"
```

## Known Issues

### Groundworks Task Configuration Bug
The Groundworks scheduled task has incorrect output folder configured:
```json
"output-folder": "/home/reporting/crawls/indagare"  // Should be groundworks
```
Fix via Chrome Remote Desktop GUI in Screaming Frog scheduled tasks.

## Future Work

- [ ] Re-implement email alerting on GCP VM
- [ ] Expected crawl schedule configuration
- [ ] Webhook support (Slack/Discord)
