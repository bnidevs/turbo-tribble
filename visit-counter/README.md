# Visit Counter

IaC definitions for a serverless visit counter: an API Gateway REST API with direct DynamoDB service integrations (no Lambda). Provided in three equivalent IaC flavors: AWS CDK (TypeScript), Terraform, and CloudFormation.

## What It Does

Each file provisions the same set of resources:

1. **DynamoDB Table** — A single table (`bnidevs.github.io-visit-tracker`) with a partition key `metric` (String) and on-demand billing. Stores a single item keyed `visits` with an `amount` attribute tracking the count.
2. **IAM Role** — Grants API Gateway permission to call `dynamodb:UpdateItem` and `dynamodb:GetItem` on the table. Nothing else.
3. **API Gateway REST API** — A public REST API (v1) with two routes:
   - `GET /visit` — Increments the counter by 1 via a DynamoDB `UpdateItem` call. Returns nothing meaningful (fire-and-forget).
   - `GET /count` — Reads the current count via a DynamoDB `GetItem` call. A response mapping template unwraps the DynamoDB JSON and returns the raw number.
4. **CORS** — Both routes include `OPTIONS` preflight handlers and return `Access-Control-Allow-Origin` headers, scoped to `https://bnidevs.github.io` by default.

There is no Lambda in this stack. API Gateway talks to DynamoDB directly using AWS service integrations and VTL mapping templates.

## How I Use This in My Projects

This is the hit counter for my GitHub Pages site. The frontend calls `GET /visit` on page load to bump the count, and `GET /count` to read it back for display.

## Files

- `visit-counter-stack.ts` — AWS CDK (TypeScript)
- `main.tf` — Terraform
- `visit-counter.yml` — CloudFormation

All three define the same infrastructure. Pick whichever matches your IaC toolchain.

## Prerequisites

No external resources are required. The stack is fully self-contained — the DynamoDB table, IAM role, and API Gateway are all created by the templates.

However, the `GET /visit` route's `UpdateExpression` (`SET amount = amount + :num`) requires the item to already exist with an `amount` attribute. If the item is missing, the update will fail. See [Deployment Notes](#deployment-notes) for how each IaC flavor handles this.

## Deployment Notes

### Seeding the Counter Item

The `UpdateExpression` used by `GET /visit` adds to an existing `amount` attribute — it doesn't create it. If the DynamoDB item doesn't exist yet, the call fails.

- **Terraform** — Uses `aws_dynamodb_table_item` to seed the item with `amount: 0` on first apply. The `lifecycle { ignore_changes = [item] }` block prevents Terraform from resetting the counter on subsequent applies.
- **CDK** — Uses an `AwsCustomResource` to call `PutItem` with a `ConditionExpression: "attribute_not_exists(metric)"` so it only seeds on initial creation and won't overwrite an existing count.
- **CloudFormation** — Has no native resource for writing a DynamoDB item. You'll need to seed it manually after deploy:

```sh
aws dynamodb put-item \
  --table-name bnidevs.github.io-visit-tracker \
  --item '{"metric": {"S": "visits"}, "amount": {"N": "0"}}' \
  --condition-expression "attribute_not_exists(metric)"
```

### CDK CORS Handling

CDK's `defaultCorsPreflightOptions` on the `RestApi` construct automatically generates `OPTIONS` methods for every resource. The Terraform and CloudFormation templates define these manually.

### Redeployment

API Gateway requires an explicit deployment resource to push changes to a stage. Terraform uses a `triggers` block with a SHA hash of the relevant resources to force redeployment on changes. CloudFormation uses `DependsOn` to sequence the deployment after all methods are defined. CDK handles this automatically.