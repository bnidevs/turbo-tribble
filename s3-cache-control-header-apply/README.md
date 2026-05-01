# S3 Cache-Control Header Applier Lambda

A lightweight AWS Lambda function that scans an S3 bucket and applies a `Cache-Control` header to objects matching a set of file extensions. Can be used standalone or as a stage in an AWS CodePipeline.

## What It Does

When invoked, this Lambda:

1. Paginates through all objects in the specified S3 bucket.
2. Filters for objects matching a set of static asset extensions (`.ico`, `.avif`, `.jpg`, `.jpeg`, `.svg`).
3. Copies each matching object onto itself with `MetadataDirective='REPLACE'`, setting `Cache-Control: max-age=31536000` (1 year).
4. Returns a count of updated objects.

That's it. It's a single-purpose function meant to ensure long-lived browser caching headers on static assets after a deployment.

## How I Use This in My Projects

This is one of the cleanup Lambda functions I use in my website pipelines that deploy static sites to S3 buckets fronted by CloudFront distributions.

S3 doesn't automatically set `Cache-Control` headers on uploaded objects. If you're deploying via CodePipeline (or any CI/CD tool that syncs files to S3), your assets will land without cache headers unless you explicitly set them during upload. Most pipeline deploy actions don't support per-extension metadata rules.

This Lambda runs after the deploy stage and retroactively stamps the correct `Cache-Control` header onto image and icon files that benefit from aggressive browser caching. It preserves the original `ContentType` and user-defined `Metadata` on each object.

It is important to know that the bucket that I apply this Lambda to does not have object versioning turned on. If in the case you have a bucket where object versioning is turned on, this Lambda realistically needs only to run once, the first time the bucket is populated. Future object uploads for objects that already exist will keep the Cache-Control header from the previous version. An optimization for this Lambda in that case would be to only write the Cache-Control header to newly uploaded objects, reducing S3 costs.

## Setup

1. Replace the placeholder `BUCKET` value in `lambda_function.py` with your actual S3 bucket name.
2. Adjust `EXTENSIONS` if you want to target additional file types (e.g., `.png`, `.webp`, `.woff2`, `.css`, `.js`).
3. Adjust `CACHE_CONTROL` if you want a different max-age value.
4. Ensure the Lambda's execution role has `s3:ListBucket`, `s3:GetObject`, and `s3:PutObject` permissions on the target bucket.

## Two Modes of Use

The code between the `STRICT LOGIC START` and `STRICT LOGIC END` comments is the core cache-header logic. Everything outside that block is CodePipeline integration glue. You can deploy this Lambda in either mode depending on your use case.

### Mode 1: Standalone Lambda (No CodePipeline)

Use this when you want to apply cache headers manually, on a schedule (e.g., EventBridge cron), or from any non-CodePipeline source.

**What to change:** Extract only the logic between `STRICT LOGIC START` and `STRICT LOGIC END`, and remove the `codepipeline.put_job_success_result(...)` call within that block. Remove the surrounding `try/except` that reports failures back to CodePipeline. Your handler becomes:

```python
import boto3

BUCKET = 'YOUR_BUCKET_NAME'
CACHE_CONTROL = 'max-age=31536000'
EXTENSIONS = {'.ico', '.avif', '.jpg', '.jpeg', '.svg'}

s3 = boto3.client('s3')

def lambda_handler(event, context):
    paginator = s3.get_paginator('list_objects_v2')
    updated = 0

    for page in paginator.paginate(Bucket=BUCKET):
        for obj in page.get('Contents', []):
            key = obj['Key']
            if not any(key.lower().endswith(ext) for ext in EXTENSIONS):
                continue

            head = s3.head_object(Bucket=BUCKET, Key=key)

            s3.copy_object(
                Bucket=BUCKET,
                Key=key,
                CopySource={'Bucket': BUCKET, 'Key': key},
                MetadataDirective='REPLACE',
                CacheControl=CACHE_CONTROL,
                ContentType=head.get('ContentType', 'application/octet-stream'),
                Metadata=head.get('Metadata', {}),
            )
            updated += 1
            print(f'Updated: {key}')

    return {'updated': updated}
```

### Mode 2: CodePipeline Action (As Provided)

Use this when the Lambda is configured as an **Invoke** action in a CodePipeline stage (typically after a deploy stage).

**How it works:** CodePipeline passes a job ID in the event payload. The Lambda calls `put_job_success_result` on success or `put_job_failure_result` on failure, which tells the pipeline whether to proceed or halt.

**Additional IAM permissions required:**
- `codepipeline:PutJobSuccessResult`
- `codepipeline:PutJobFailureResult`

Use the file as-is (with your bucket name substituted) for this mode.

## IAM Policy (Minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codepipeline:PutJobSuccessResult",
        "codepipeline:PutJobFailureResult"
      ],
      "Resource": "*"
    }
  ]
}
```

Drop the `codepipeline` statement if using standalone mode.

## Notes

- The function uses `copy_object` with `MetadataDirective='REPLACE'` to update metadata in place. This replaces **all** system-defined metadata on the object. `ContentType` and user-defined `Metadata` are explicitly preserved; other headers (e.g., `ContentEncoding`, `ContentDisposition`, `StorageClass`) are not.
- The function updates every matching object on every invocation, regardless of whether the `Cache-Control` header is already set correctly. For buckets with many matching objects, consider adding a check against the existing header to skip unnecessary copies.
- Lambda has a default timeout of 3 seconds. For buckets with many objects, increase the timeout in your Lambda configuration. A timeout of 60–300 seconds is reasonable for most static site buckets.
- Each matching object incurs one `HeadObject` call and one `CopyObject` call. For large buckets, be aware of S3 request costs.
