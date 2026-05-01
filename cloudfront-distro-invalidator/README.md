# CloudFront Distribution Invalidator Lambda

A lightweight AWS Lambda function that creates a wildcard cache invalidation (`/*`) on a specified CloudFront distribution. Can be used standalone or as a stage in an AWS CodePipeline.

## What It Does

When invoked, this Lambda:

1. Creates a CloudFront invalidation for all paths (`/*`) on a hardcoded distribution ID.
2. Returns the invalidation ID and status.

That's it. It's a single-purpose function meant to bust CloudFront's cache after a deployment.

## How I Use This in My Projects

This is one of the cleanup Lambda functions I use in my website pipelines that deploy CloudFront distributions from S3 buckets or other code sources.

If your CloudFront distribution cache policy is not set to CachingDisabled (which for me, some of my distributions are set to CachingOptimized), there is a TTL for possibly outdated content on CloudFront.

On the CachingOptimized policy, this is set to a default of 24 hours but a minimum of 1 second and a maximum of 365 days.

In order to immediately clear the CloudFront distribution cache and replace with new content, the easiest way is to invalidate the cache, which is done via this script.

## Setup

1. Replace the placeholder `dist_id` value in `lambda_function.py` with your actual CloudFront Distribution ID (e.g., `E1A2B3C4D5E6F7`). This is the short distribution ID, **not** the full ARN.
2. Ensure the Lambda's execution role has the `cloudfront:CreateInvalidation` permission.

## Two Modes of Use

The code between the `STRICT LOGIC START` and `STRICT LOGIC END` comments is the core invalidation logic. Everything outside that block is CodePipeline integration glue. You can deploy this Lambda in either mode depending on your use case.

### Mode 1: Standalone Lambda (No CodePipeline)

Use this when you want to trigger invalidations manually, on a schedule (e.g., EventBridge cron), or from any non-CodePipeline source.

**What to change:** Extract only the logic between `STRICT LOGIC START` and `STRICT LOGIC END`, and remove the `codepipeline.put_job_success_result(...)` call within that block. Remove the surrounding `try/except` that reports failures back to CodePipeline. Your handler becomes:

```python
import boto3
import time

def lambda_handler(event, context):
    cf = boto3.client('cloudfront')
    dist_id = 'YOUR_DISTRIBUTION_ID'
    resp = cf.create_invalidation(
        DistributionId=dist_id,
        InvalidationBatch={
            'Paths': {'Quantity': 1, 'Items': ['/*']},
            'CallerReference': str(time.time()),
        },
    )
    return {
        'statusCode': 200,
        'invalidation_id': resp['Invalidation']['Id'],
        'status': resp['Invalidation']['Status'],
    }
```

### Mode 2: CodePipeline Action (As Provided)

Use this when the Lambda is configured as an **Invoke** action in a CodePipeline stage (typically after a deploy stage).

**How it works:** CodePipeline passes a job ID in the event payload. The Lambda calls `put_job_success_result` on success or `put_job_failure_result` on failure, which tells the pipeline whether to proceed or halt.

**Additional IAM permissions required:**
- `codepipeline:PutJobSuccessResult`
- `codepipeline:PutJobFailureResult`

Use the file as-is (with your distribution ID substituted) for this mode.

## IAM Policy (Minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::YOUR_ACCOUNT_ID:distribution/YOUR_DISTRIBUTION_ID"
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

- CloudFront invalidations are **not instant**. The returned `status` will be `InProgress`. The function does not wait for completion.
- AWS provides 1,000 free invalidation paths per month. A single `/*` wildcard counts as one path.
- `CallerReference` uses `time.time()` to ensure uniqueness. This is fine for non-concurrent invocations but could collide if two invocations fire within the same fractional second.
