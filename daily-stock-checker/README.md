# Daily Stock Checker Lambda

A lightweight AWS Lambda function that checks the current price of a stock against a target price and sends a notification via SNS. Designed to run on a daily schedule via EventBridge.

## What It Does

When invoked, this Lambda:

1. Checks whether today is a NASDAQ market holiday. If so, exits early.
2. Fetches the current stock price from the Financial Modeling Prep API.
3. Calculates the distance (dollar and percentage) from a hardcoded target price.
4. Fetches a random quote from the ZenQuotes API.
5. Publishes a formatted message to an SNS topic with the price update and the quote.

## Setup

1. Replace the placeholder `API_KEY` value in `lambda_function.py` with your Financial Modeling Prep API key.
2. Replace the placeholder `TopicArn` value with your actual SNS Topic ARN.
3. Optionally change the `STOCK` and `TARGET` constants to track a different ticker or target price.
4. Ensure the Lambda's execution role has the `sns:Publish` permission for the target SNS topic.
5. The Lambda needs outbound internet access (not in a VPC, or in a VPC with a NAT gateway) to reach the Financial Modeling Prep and ZenQuotes APIs.

## Scheduling

This is meant to run on a daily schedule. Set up an EventBridge rule with a cron expression targeting trading hours, e.g.:

```
cron(0 18 ? * MON-FRI *)
```

This fires at 6:00 PM UTC (around market close) on weekdays. The holiday check handles the rest.

## IAM Policy (Minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "YOUR_SNS_TOPIC_ARN"
    }
  ]
}
```

## Notes

- The holiday check only covers NASDAQ exchange holidays. Weekend filtering should be handled by your EventBridge cron expression (e.g., `MON-FRI`).
- `API_KEY` is hardcoded in the source. For anything beyond a personal project, move it to AWS Secrets Manager or an environment variable with KMS encryption.
- The ZenQuotes API is rate-limited on its free tier. If it goes down or rate-limits you, the Lambda will throw an unhandled exception. Consider wrapping that call in a try/except if uptime matters.
- `TARGET` is a static value. If you want dynamic target tracking, you'd need to pull it from a parameter store or database.
