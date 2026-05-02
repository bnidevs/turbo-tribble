# Daily Stock Checker

An AWS Lambda function that checks the current price of a stock against a target price and sends a notification via SNS. Designed to run on a daily schedule via EventBridge.

## What It Does

When invoked, this Lambda:

1. Checks whether today is a NASDAQ market holiday. If so, exits early.
2. Fetches the current stock price from the Financial Modeling Prep API.
3. Calculates the distance (dollar and percentage) from the target price.
4. Fetches a random quote from the ZenQuotes API.
5. Publishes a formatted message to an SNS topic with the price update and the quote.

## Project Structure

```
├── lambda_function.py                  # Lambda source code
├── main.tf                             # Terraform
├── daily-stock-checker-stack.ts        # AWS CDK (TypeScript)
├── template.yaml                       # CloudFormation
└── README.md
```

Three IaC options are included. Pick one — they all produce the same infrastructure.

## Infrastructure Created

All three IaC files provision:

- A Lambda function (`daily-stock-checker`) running Python 3.12
- An IAM role with permissions for SNS publish and CloudWatch Logs
- An EventBridge rule that triggers the Lambda Monday–Friday at 5:00 PM UTC
- A Lambda permission granting EventBridge invocation rights

## Configuration

All configuration is passed to the Lambda via environment variables:

| Variable | Required | Description |
|---|---|---|
| `API_KEY` | Yes | Financial Modeling Prep API key |
| `SNS_TOPIC_ARN` | Yes | ARN of the SNS topic for notifications |
| `STOCK` | No | Ticker symbol (default: `AMZN`) |
| `TARGET` | No | Target price (default: `300`) |

Each IaC option accepts these as input parameters/variables — see the relevant file for specifics.

## Deployment

### Terraform

```bash
terraform init
terraform apply \
  -var="sns_topic_arn=arn:aws:sns:us-east-1:123456789012:my-topic" \
  -var="fmp_api_key=your-api-key"
```

Place `lambda_function.py` in the same directory as `main.tf`. Terraform zips it automatically.

### CDK (TypeScript)

```bash
npm install aws-cdk-lib constructs
cdk deploy \
  -c snsTopicArn="arn:aws:sns:us-east-1:123456789012:my-topic" \
  -c fmpApiKey="your-api-key"
```

Place `lambda_function.py` in a `lambda/` directory relative to the CDK project root.

### CloudFormation

```bash
# Zip and upload the Lambda code
zip lambda_function.zip lambda_function.py
aws s3 cp lambda_function.zip s3://your-bucket/daily-stock-checker/lambda_function.zip

# Deploy the stack
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name daily-stock-checker \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    SnsTopicArn="arn:aws:sns:us-east-1:123456789012:my-topic" \
    FmpApiKey="your-api-key" \
    S3Bucket="your-bucket"
```

## Notes

- The EventBridge cron handles weekday filtering (`MON-FRI`). The Lambda's holiday check covers NASDAQ exchange holidays.
- The API key is passed as a plaintext environment variable. For anything beyond a personal project, use AWS Secrets Manager or SSM Parameter Store with KMS encryption.
- The ZenQuotes API is rate-limited on its free tier. If it goes down, the Lambda will throw an unhandled exception. Consider wrapping that call in a try/except if uptime matters.
- The schedule is 5:00 PM **UTC**. Adjust the cron expression if you need a different timezone (e.g., `cron(0 21 ? * MON-FRI *)` for 5 PM Eastern during EDT).