# turbo-tribble
helpful snippets that i use and have used in my projects

---

These are production snippets extracted from real pipelines — not tutorials or boilerplate, that I use or have used in current or past projects.

## What's In Here

### [`static-website-codepipeline/`](static-website-codepipeline/)
A full AWS CodePipeline definition for static site deployment, provided in three equivalent IaC flavors (CDK, Terraform, CloudFormation). Implements a five-stage pipeline: Source → Staging → Manual Approval → Production → Cleanup. The cleanup stage invokes the two Lambdas below in sequence.

### [`s3-cache-control-header-apply/`](s3-cache-control-header-apply/)
Lambda function that scans an S3 bucket and stamps `Cache-Control: max-age=31536000` on static assets (images, icons, SVGs). Runs as a CodePipeline action or standalone. Necessary because S3 deploy actions don't set per-extension cache headers on upload.

### [`cloudfront-distro-invalidator/`](cloudfront-distro-invalidator/)
Lambda function that creates a wildcard cache invalidation (`/*`) on a CloudFront distribution. Runs as a CodePipeline action or standalone. Ensures users see the latest content immediately after a deploy rather than waiting for TTL expiry.

### [`daily-stock-checker/`](daily-stock-checker/)
Lambda function that checks a stock price against a target, calculates the distance, and sends an SNS notification with the update and a random quote. Designed to run on a daily EventBridge schedule, skipping NASDAQ holidays.

### [`ping-me/`](ping-me/)
Lambda function behind API Gateway that lets anyone with the URL send you an SNS notification. A simple public "ping me" endpoint with no auth.

## License

[GPL-3.0](LICENSE)
