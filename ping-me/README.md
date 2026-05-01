# Ping Me Lambda

A lightweight AWS Lambda function that publishes a message to an SNS topic. Exposed via API Gateway so anyone with the URL can trigger a notification.

## What It Does

When invoked via its API Gateway endpoint, this Lambda:

1. Reads the `msg` query string parameter from the request URL.
2. Publishes the message to a hardcoded SNS topic.
3. Returns the SNS publish response.

If no `msg` parameter is provided, it sends a default message (`ping-me default message`).

## How I Use This in My Projects

I have this Lambda sitting behind a public API Gateway endpoint. Anyone with the link can hit the URL and send me a notification — no auth required.

The SNS topic on the other end is subscribed to whatever notification channel I want (email, SMS, etc.), so it acts as a simple "ping me" button for the internet.

## Example Usage

```
GET https://your-api-id.execute-api.us-east-1.amazonaws.com/default/ping-me?msg=hey+are+you+around
```

This sends an SNS notification with the message: `ping-me message: hey+are+you+around`

To use the default message, hit the endpoint with no query string:

```
GET https://your-api-id.execute-api.us-east-1.amazonaws.com/default/ping-me
```

## Setup

1. Replace `INSERT SNS TOPIC ARN HERE` in `lambda_function.py` with your actual SNS Topic ARN (e.g., `arn:aws:sns:us-east-1:123456789012:ping-me-topic`).
2. Ensure the Lambda's execution role has the `sns:Publish` permission for that topic.
3. Create an API Gateway trigger (HTTP API or REST API) pointed at this Lambda. No authorization is required if you want the endpoint to be publicly accessible.

## IAM Policy (Minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:YOUR_REGION:YOUR_ACCOUNT_ID:YOUR_TOPIC_NAME"
    }
  ]
}
```

## Notes

- The query string is parsed manually via `split`. URL-encoded characters (e.g., `%20`, `+`) are **not** decoded — they will appear as-is in the notification message.
- There is no authentication or rate limiting beyond API Gateway's default throttling (10,000 requests per second by default on HTTP APIs). Anyone with the URL can invoke this Lambda.
- The message is double-JSON-encoded via `MessageStructure='json'` with a `default` key. This means the SNS topic will deliver the raw JSON string of the message to protocol-specific subscribers. If your subscriber expects plain text, you may want to simplify the publish call.
