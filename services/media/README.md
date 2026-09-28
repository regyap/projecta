# Optional image labeling worker

Enable `enable_media_pipeline = true` in the existing dev Terraform environment.
Geolocation also requires `enable_geolocation = true`; both default off. No faces,
identity recognition, tracking or location inference from images is implemented.

Upload a JPEG/PNG up to 5 MiB to `input/` with the correct Content-Type, using an
operator identity permitted for this dedicated bucket. The worker role cannot upload
inputs. A user-facing upload API/authentication/presigned upload policy is future work.
S3 sends a versioned event to a standard SQS queue. Lambda writes coarse labels into
`results/`. The two prefixes prevent recursive notifications. This queue is independent
of the deployment FIFO queue, and cannot trigger code deployment.

Example (after applying, substitute the output bucket):

```powershell
aws s3api put-object --region ap-southeast-1 --bucket <media-bucket> --key input/sample.jpg --body sample.jpg --content-type image/jpeg
```

Optional user-provided S3 metadata: `location-consent=true`, `latitude`, `longitude`.
These values must come from a consenting user, not inferred from EXIF or IP addresses.
Both the deployment switch and per-object consent must be enabled to call Amazon
Location. Coordinate validation uses `[longitude, latitude]`. Reverse geocoding uses
`IntendedUse=Storage` because coarse results are retained. Raw image metadata still
contains the supplied coordinates: the upload interface must explain retention.

Inputs/results expire after 30 days; noncurrent versions after 7 days (asynchronous
S3 lifecycle, not immediate deletion). No coordinates or image keys are logged.
Results have a deterministic key per immutable input version. At-least-once delivery
can repeat paid API calls and create result versions; it does not promise exactly-once
processing. Partial batch failures retry; after five receives messages reach the DLQ.
Alarms are created without notification recipients; wire those before operational use.
Deleting the Lambda is not cleanup: drain/delete the media resources explicitly.
