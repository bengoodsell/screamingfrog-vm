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
When `monitor-crawl-emails` detects a new crawl completion email, it publishes to the `crawl-complete` Pub/Sub topic. This triggers `trigger-vm-pipeline` which SSHs into the VM and runs the pipeline. After successful upload, a Cloud Task is queued to trigger `screamingfrog-raw-to-pub` after a 5-minute delay (allowing bqdl to finish importing).

```
monitor-crawl-emails (every 30 min)
    │
    ├─→ Detects new crawl completion email
    │
    └─→ Publishes to Pub/Sub: crawl-complete
            │
            └─→ trigger-vm-pipeline Cloud Function
                    │
                    ├─→ SSH to VM → run.sh → GCS upload
                    │
                    └─→ Queue Cloud Task (5 min delay)
                            │
                            └─→ screamingfrog-raw-to-pub → pub tables
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
screamingfrog-raw-to-pub (Cloud Task, 5 min after upload)
    ↓
BigQuery: screamingfrog.*_pub tables
```

Note: The 6-hour scheduled job remains as a fallback if the Cloud Task fails.

## Cloud Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `bqdl` | Eventarc (GCS upload) | Import CSVs to BigQuery |
| `monitor-crawl-emails` | Cloud Scheduler (30 min) | Track crawl completion, publish to Pub/Sub |
| `trigger-vm-pipeline` | Pub/Sub (crawl-complete) | SSH to VM, run pipeline, queue raw→pub task |
| `screamingfrog-raw-to-pub` | Cloud Tasks (5 min delay) + Scheduler (6 hours fallback) | Transform raw → pub |
| `delete-test-crawl` | HTTP | Remove test crawls |

## BigQuery Tables

### Dataset: `screamingfrog`

| Table | Description |
|-------|-------------|
| `internal_raw` / `internal_pub` | Main crawl data |
| `issues_raw` / `issues_pub` | SEO issues (key columns: `file_path`, `upload_date`, `crawl_date`) |
| `overview_raw` / `overview_pub` | Crawl overview |
| `segments_raw` / `segments_pub` | URL segments |
| `crawl_emails` | Email tracking (key columns: `email_id`, `crawl_name`, `received_timestamp`, `client`) |
| `pipeline_alerts` | Alert suppression |
| `pipeline_triggers` | Event-driven trigger audit log (key columns: `email_id`, `client`, `trigger_timestamp`, `success`, `error_message`) |

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
- **Cloud Tasks Queue**: `screamingfrog-raw-to-pub-queue` (us-central1)

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

## Debugging Pipeline Issues

When data isn't appearing in dashboards, follow this diagnostic decision tree:

### Decision Tree
```
pipeline_triggers shows success=true?
├── YES → Check GCS for files
│         ├── Files exist → Check bqdl logs and BigQuery raw tables
│         │                 └── Raw has data? → Check if raw→pub has run
│         └── Files missing → Check VM pipeline.log for upload errors
│
└── NO or no record → Trigger chain failed
          ├── Check monitor-crawl-emails logs (did it detect the email?)
          └── Check trigger-vm-pipeline logs (SSH failure?)
```

### Step 1: Check crawl_emails (email detection)
```sql
SELECT email_id, crawl_name, received_timestamp, client
FROM `tight-ship-consulting.screamingfrog.crawl_emails`
WHERE LOWER(crawl_name) LIKE "%<client>%"
ORDER BY received_timestamp DESC LIMIT 10;
```

### Step 2: Check pipeline_triggers (trigger fired?)
```sql
SELECT email_id, client, trigger_timestamp, success, error_message
FROM `tight-ship-consulting.screamingfrog.pipeline_triggers`
WHERE client = '<client>'
ORDER BY trigger_timestamp DESC LIMIT 10;
```

### Step 3: Check Cloud Function Logs
```bash
# Email monitoring function
gcloud functions logs read monitor-crawl-emails --region=us-central1 --gen2 --limit=50

# Pipeline trigger function
gcloud functions logs read trigger-vm-pipeline --region=us-east4 --gen2 --limit=30

# BigQuery import function
gcloud functions logs read bqdl --region=us-east4 --gen2 --limit=50
```

### Step 4: Check GCS for Uploaded Files
```bash
gcloud storage ls "gs://bqdl-uploads/screamingfrog/<client>/"
```

### Step 5: Check VM Pipeline Log
```bash
gcloud compute ssh screaming-frog --zone=us-east4-a --command="sudo cat /home/reporting/screamingfrog-vm/scripts/logs/pipeline.log | tail -100"
```

### Step 6: Check BigQuery Raw vs Pub Tables
```sql
-- Raw table (populated shortly after upload)
SELECT file_path, upload_date, crawl_date, COUNT(*) as row_count
FROM `tight-ship-consulting.screamingfrog.issues_raw`
WHERE file_path LIKE '%<client>%'
GROUP BY 1, 2, 3 ORDER BY upload_date DESC LIMIT 10;

-- Pub table (transforms every 6 hours)
SELECT file_path, crawl_date, COUNT(*) as row_count
FROM `tight-ship-consulting.screamingfrog.issues_pub`
WHERE file_path LIKE '%<client>%'
GROUP BY 1, 2 ORDER BY crawl_date DESC LIMIT 10;
```

### Step 7: Manually Trigger Raw→Pub Transform
If data is in `_raw` but not in `_pub`, manually trigger the transform:
```bash
gcloud functions call screamingfrog-raw-to-pub --region=us-central1 --gen2
```
Note: The raw→pub transform is automatically triggered ~5 minutes after each crawl upload via Cloud Tasks. The 6-hour scheduled job remains as a fallback.

### Step 8: Check Cloud Tasks Queue
```bash
gcloud tasks list --queue=screamingfrog-raw-to-pub-queue --location=us-central1
```

### Pause/Resume Cloud Tasks (Emergency)
If the raw→pub triggers are causing issues:
```bash
# Pause the queue (tasks will accumulate but not execute)
gcloud tasks queues pause screamingfrog-raw-to-pub-queue --location=us-central1

# Resume the queue
gcloud tasks queues resume screamingfrog-raw-to-pub-queue --location=us-central1
```

## Future Work

- [x] Re-implement email alerting on GCP VM
- [x] Event-driven pipeline trigger on crawl completion
- [x] Event-driven raw→pub transform (Cloud Tasks with 5 min delay)
- [ ] Expected crawl schedule configuration
- [ ] Webhook support (Slack/Discord)
