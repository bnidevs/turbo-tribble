# Ping Me

A lightweight AWS Lambda function behind an HTTP API Gateway that publishes messages to an SNS topic. Hit the URL, get a notification.

## Architecture

```
GET /ping-me?msg=hello
        │
        ▼
  ┌───────────────┐
  │  API Gateway  │
  │  HTTP API v2  │
  └──────┬────────┘
         │ (payload format 2.0)
         ▼
  ┌───────────────┐
  │    Lambda      │
  │  (Python 3.13) │
  └──────┬────────┘
         │
         ▼
  ┌───────────────┐
  │   SNS Topic   │
  └───────────────┘
         │
         ▼
   subscribers
  (email, SMS, etc.)
```

## Usage

```
GET https://<api-id>.execute-api.<region>.amazonaws.com/prod/ping-me?msg=hey+are+you+around
```

Returns:

```json
{
  "message": "hey are you around",
  "messageId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Omit the `msg` parameter to send the default message (`ping-me default message`).

## Project Structure

```
.
├── lambda_function.py     # Lambda handler
├── main.tf                # Terraform
├── ping-me-stack.ts       # CDK (TypeScript)
└── ping-me-cfn.yml        # CloudFormation
```

Three IaC templates are included. They all deploy the same infrastructure — pick whichever matches your workflow.

## Deploying

### Prerequisites

- Package the Lambda code into a zip:

  ```bash
  zip lambda.zip lambda_function.py
  ```

- The Lambda function reads `SNS_TOPIC_ARN` from its environment. All three templates set this automatically — no hardcoded ARNs.

### Terraform

```bash
terraform init
terraform apply -var="aws_region=us-east-1"
```

The `lambda_zip_path` variable defaults to `lambda.zip` in the working directory. Override it with `-var="lambda_zip_path=path/to/your.zip"` if needed.

### CDK (TypeScript)

Expects the Lambda code in a `lambda/` directory alongside the stack file:

```
.
├── lambda/
│   └── lambda_function.py
└── ping-me-stack.ts
```

```bash
npx cdk deploy
```

Region and account are pulled from `CDK_DEFAULT_REGION` and `CDK_DEFAULT_ACCOUNT` environment variables, falling back to `us-east-1`.

### CloudFormation

Upload `lambda.zip` to an S3 bucket, then deploy:

```bash
aws cloudformation deploy \
  --template-file ping-me-cfn.yml \
  --stack-name ping-me \
  --parameter-overrides \
      LambdaS3Bucket=your-bucket \
      LambdaS3Key=ping-me/lambda.zip \
  --capabilities CAPABILITY_NAMED_IAM
```

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `aws_region` / region | `us-east-1` | AWS region to deploy into |
| `stage_name` / `StageName` | `prod` | API Gateway stage name |
| Lambda zip path | `lambda.zip` | Path or S3 location of the deployment package |

## Security Considerations

- **No authentication.** The endpoint is publicly accessible. Anyone with the URL can invoke the Lambda and publish to your SNS topic.
- **No rate limiting** beyond API Gateway's default throttling (10,000 req/s on HTTP APIs). If abuse is a concern, configure throttling on the stage or add an API key / authorizer.
- **IAM is least-privilege.** The Lambda role has only `sns:Publish` on the specific topic plus basic CloudWatch Logs permissions.

## SNS Subscriptions

The templates create the topic but do not wire up any subscriptions. Add those separately via the console, CLI, or IaC depending on how you want to be notified (email, SMS, webhook, etc.).