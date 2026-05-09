# turbo-tribble
helpful snippets that i use and have used in my projects

---

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/bnidevs/turbo-tribble/main.yml?label=iac-lint)

## What's In Here

### [`static-website-scaffolding/`](static-website-scaffolding/)
IaC definitions for the foundational infrastructure behind a static website: an S3 bucket with public static hosting, a CloudFront distribution serving the bucket over HTTPS, a Route 53 hosted zone, and an ACM certificate with automated DNS validation. Provided in three equivalent IaC flavors (CDK, Terraform, CloudFormation). This is the base layer that [`static-website-codepipeline/`](static-website-codepipeline/) deploys into.

### [`static-website-codepipeline/`](static-website-codepipeline/)
A full AWS CodePipeline definition for static site deployment, provided in three equivalent IaC flavors (CDK, Terraform, CloudFormation). Implements a five-stage pipeline: Source → Staging → Manual Approval → Production → Cleanup. The cleanup stage invokes the two Lambdas below in sequence.

### [`s3-cache-control-header-apply/`](s3-cache-control-header-apply/)
Lambda function that scans an S3 bucket and stamps `Cache-Control: max-age=31536000` on static assets (images, icons, SVGs). Runs as a CodePipeline action or standalone. Necessary because S3 deploy actions don't set per-extension cache headers on upload.

### [`cloudfront-distro-invalidator/`](cloudfront-distro-invalidator/)
Lambda function that creates a wildcard cache invalidation (`/*`) on a CloudFront distribution. Runs as a CodePipeline action or standalone. Ensures users see the latest content immediately after a deploy rather than waiting for TTL expiry.

### [`pagespeed-insights-to-cloudwatch-metrics/`](pagespeed-insights-to-cloudwatch-metrics/)
Lambda function that fetches Google PageSpeed Insights scores for a list of URLs and publishes them as custom CloudWatch metrics. Runs as a post-deploy benchmark in website pipelines, snapshotting Lighthouse scores (accessibility, best practices, performance, SEO) for both mobile and desktop strategies.

### [`visit-counter/`](visit-counter/)
IaC definitions for a serverless visit counter: an API Gateway REST API with direct DynamoDB service integrations (no Lambda). `GET /visit` increments the counter, `GET /count` reads it back. CORS is scoped to a single allowed origin. Provided in three equivalent IaC flavors (CDK, Terraform, CloudFormation).

### [`daily-stock-checker/`](daily-stock-checker/)
Lambda function that checks a stock price against a target, calculates the distance, and sends an SNS notification with the update and a random quote. Designed to run on a daily EventBridge schedule, skipping NASDAQ holidays. Provided in three IaC flavors (CDK, Terraform, CloudFormation) that provision the Lambda, IAM role, and EventBridge schedule.

### [`ping-me/`](ping-me/)
Lambda function behind an HTTP API Gateway (v2) that lets anyone with the URL send you an SNS notification. A simple public "ping me" endpoint with no auth. Provided in three IaC flavors (CDK, Terraform, CloudFormation) that provision the Lambda, API Gateway, SNS topic, and IAM role.

### [`scroll-converter/`](scroll-converter/)
Minimal JavaScript snippet that converts vertical mouse wheel input into horizontal scrolling. Intended for elements with `overflow-x: scroll` and `overflow-y: hidden` where traditional mouse wheels would otherwise be useless. No dependencies, no build step.

### [`workflows/`](workflows/)
GitHub Actions workflows for build, test, and release automation. Currently contains:

- **[`macos-app-release/`](workflows/macos-app-release/)** — Builds, archives, and publishes a macOS app as a GitHub Release (`.dmg` + `.zip`) on version tag push.

## License

[GPL-3.0](LICENSE)
