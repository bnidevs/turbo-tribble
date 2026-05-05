# PageSpeed Insights to CloudWatch Metrics Lambda

A lightweight AWS Lambda function that fetches Google PageSpeed Insights scores for a list of URLs and publishes them as custom CloudWatch metrics. Useful for tracking Lighthouse scores over time and setting up alarms on performance regressions.

## What It Does

When invoked, this Lambda:

1. Iterates over a list of target URLs, strategies (mobile/desktop), and Lighthouse categories (accessibility, best-practices, performance, seo).
2. Calls the Google PageSpeed Insights API for each combination.
3. Publishes the resulting scores (scaled 0–100) as custom CloudWatch metrics under the `PageSpeed Insights` namespace.

That's it. It's a single-purpose function meant to snapshot your Lighthouse scores into CloudWatch so you can graph them, alert on them, or feed them into dashboards.

## How I Use This in My Projects

This runs as a post-deploy benchmark in my website pipelines. After a deployment finishes (e.g., as a later stage in CodePipeline, or invoked by whatever triggers your deploys), this Lambda hits the freshly deployed site and snapshots the Lighthouse scores into CloudWatch. That way every deploy gets a scorecard, and I can see if a change tanked performance or accessibility.

Once the metrics are in CloudWatch, you can graph them over time, set alarms — for example, alert if mobile performance drops below 80 — or pipe them into Grafana, Datadog, or whatever else reads CloudWatch.

## Setup

1. Replace the placeholder values in `lambda_function.py`:
   - Add your target URLs to the `TARGET_URLS` list.
   - Replace `'INSERT PAGESPEED INSIGHTS API KEY HERE'` with your actual [PageSpeed Insights API key](https://developers.google.com/speed/docs/insights/v5/get-started#key).
2. Ensure the Lambda's execution role has the `cloudwatch:PutMetricData` permission.
3. Set the Lambda timeout to something reasonable. Each API call can take several seconds, and you're making `len(TARGET_URLS) × 2 × 4` calls sequentially. For a single URL, 30 seconds is usually fine. For several, bump it up or consider the note below on batching API calls.

## IAM Policy (Minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "cloudwatch:PutMetricData",
      "Resource": "*"
    }
  ]
}
```

`PutMetricData` does not support resource-level permissions, so the resource must be `*`.

## CloudWatch Metric Structure

Each published metric has the following shape:

- **Namespace:** `PageSpeed Insights`
- **MetricName:** `LighthouseScore`
- **Dimensions:**
  - `URL` — the target URL
  - `Strategy` — `mobile` or `desktop`
  - `Category` — `accessibility`, `best-practices`, `performance`, or `seo`
- **Value:** 0–100 (the raw Lighthouse score multiplied by 100)

## Notes

- The PageSpeed Insights API has a default quota of 25,000 queries per day for free-tier keys. At 8 calls per URL per invocation, you have plenty of headroom for scheduled runs.
- API calls are made **sequentially**. For a single URL this produces 8 requests (2 strategies × 4 categories). If you add many URLs, Lambda execution time will scale linearly — factor this into your timeout setting.
- The function silently swallows individual API errors and continues to the next combination. Failed fetches are logged but won't prevent the remaining metrics from being published. This means a partial failure won't zero out your dashboard, but it also means you should monitor your Lambda logs for recurring errors.
- `PutMetricData` accepts up to 1,000 metrics per call. The current design publishes all metrics in a single batch, which is fine for any reasonable number of URLs.
- The API key is hardcoded in the handler. For production use, consider pulling it from AWS Secrets Manager or an environment variable instead.
