# Screaming Frog GCP VM Pipeline

Pipeline scripts for compressing, uploading, and cleaning Screaming Frog crawl exports on GCP VM.

## VM Management

### SSH Access
```bash
# SSH into the VM
gcloud compute ssh screaming-frog --zone=us-east4-a

# Run command as reporting user
sudo -u reporting <command>

# SSH and run single command
gcloud compute ssh screaming-frog --zone=us-east4-a --command="<command>"
```

### Chrome Remote Desktop
For GUI access to Screaming Frog scheduled tasks, use Chrome Remote Desktop.
- **Access URL**: https://remotedesktop.google.com/access
- **Google Account**: `reporting@tightship.consulting`
- **Linux User**: `reporting`

#### Display Configuration (Avoiding Conflicts)
Xvfb and Chrome Remote Desktop use separate displays to avoid conflicts:

| Service | Display | Purpose |
|---------|---------|---------|
| Xvfb | `:0` | Headless display for Screaming Frog scheduled tasks |
| Chrome Remote Desktop | `:20+` | Interactive GUI access (CRD manages its own) |

The `reporting` user has `DISPLAY=:0` in `.bashrc` for headless operations.

#### Re-authorizing Chrome Remote Desktop
If CRD stops working, re-authorize via SSH:
1. Go to https://remotedesktop.google.com/headless (logged in as `reporting@tightship.consulting`)
2. Generate the Debian Linux command
3. SSH to VM and run as reporting user:
   ```bash
   sudo -u reporting <paste-command-here>
   ```

#### Color Management Dialog
On first connect, a polkit dialog may ask for "ubuntu" password to "create a color managed device". This can be safely cancelled - it doesn't affect functionality.

### VM Details
| Property | Value |
|----------|-------|
| VM Name | `screaming-frog` |
| Zone | `us-east4-a` |
| Project | `tight-ship-consulting` |
| SF User | `reporting` |
| gcloud (local Mac) | `/opt/homebrew/share/google-cloud-sdk/bin/gcloud` |
| gcloud (on VM) | `/snap/bin/gcloud` |
| Screaming Frog | `/usr/bin/screamingfrogseospider` (v23.2) |
| Xvfb Display | `:0` (for headless tasks) |

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

### Pipeline Triggers

The pipeline runs via two mechanisms:

#### 1. Event-Driven (Primary)
When `monitor-crawl-emails` detects a new crawl completion email, it publishes to the `crawl-complete` Pub/Sub topic. This triggers `trigger-vm-pipeline` which SSHs into the VM and runs the pipeline immediately.

```
monitor-crawl-emails (every 30 min)
    │
    ├─→ Detects new crawl completion email
    │
    └─→ Publishes to Pub/Sub: crawl-complete
            │
            └─→ trigger-vm-pipeline Cloud Function
                    │
                    └─→ gcloud compute ssh → run.sh
```

#### 2. Scheduled Cron (Fallback)
Daily at 7 AM as a safety net in case event-driven triggers fail:
```cron
0 7 * * * /home/reporting/screamingfrog-vm/scripts/run.sh
```

The pipeline is idempotent - `gcloud storage rsync` handles duplicate uploads gracefully.

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
| `monitor-crawl-emails` | Cloud Scheduler (30 min) | Track crawl completion, publish to Pub/Sub |
| `trigger-vm-pipeline` | Pub/Sub (crawl-complete) | SSH to VM and run pipeline |
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
| `pipeline_triggers` | Event-driven trigger audit log |

## Troubleshooting

### Check Pipeline Logs
```bash
gcloud compute ssh screaming-frog --zone=us-east4-a --command="cat /home/reporting/screamingfrog-vm/scripts/logs/pipeline.log"
```

### Verify GCS Uploads
```bash
gcloud storage ls gs://bqdl-uploads/screamingfrog/
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
gcloud compute ssh screaming-frog --zone=us-east4-a --command="sudo -u reporting /home/reporting/screamingfrog-vm/scripts/run.sh"
```

### Suppress Pipeline Alerts
```sql
INSERT INTO `tight-ship-consulting.screamingfrog.pipeline_alerts`
(client, suppressed_until, reason)
VALUES ('client_name', TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY), 'Reason');
```

### Check Pipeline Trigger History
```sql
SELECT email_id, client, trigger_timestamp, success, error_message
FROM `tight-ship-consulting.screamingfrog.pipeline_triggers`
ORDER BY trigger_timestamp DESC
LIMIT 20;
```

### Manually Trigger Pipeline via Pub/Sub
```bash
gcloud pubsub topics publish crawl-complete \
    --message='{"email_id":"manual-test","client":"test","crawl_name":"manual trigger"}'
```

### Check trigger-vm-pipeline Logs
```bash
gcloud functions logs read trigger-vm-pipeline --region=us-east4 --gen2
```

## Related Resources

- **SfAutoUpload**: `/Users/bengoods/SfAutoUpload/` (email monitoring & trigger functions)
- **GCS Bucket**: `gs://bqdl-uploads/screamingfrog`
- **GCP Project**: `tight-ship-consulting`
- **Pub/Sub Topic**: `crawl-complete` (pipeline trigger events)

## Updating Scripts

### Local Development
```bash
# Make changes locally, commit, and push
git add . && git commit -m "Update scripts" && git push
```

### Deploy to VM
```bash
gcloud compute ssh screaming-frog --zone=us-east4-a --command="cd /home/reporting/screamingfrog-vm && sudo -u reporting git pull"
```

## Known Issues

### Groundworks Task Configuration Bug
The Groundworks scheduled task has incorrect output folder configured:
```json
"output-folder": "/home/reporting/crawls/indagare"  // Should be groundworks
```
Fix via Chrome Remote Desktop GUI in Screaming Frog scheduled tasks.

## Future Work

- [x] Re-implement email alerting on GCP VM
- [x] Event-driven pipeline trigger on crawl completion
- [ ] Expected crawl schedule configuration
- [ ] Webhook support (Slack/Discord)
