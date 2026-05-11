# `.github/workflows/`

CI workflows for static analysis and security scanning. No AWS credentials required unless noted.

---

### [`cfn-lint.yml`](cfn-lint.yml)
Runs [cfn-lint](https://github.com/aws-cloudformation/cfn-lint) against CloudFormation templates on push and PR. Auto-detects templates by grepping for `AWSTemplateFormatVersion` or `Resources:` in the first 20 lines. Scoped to `.yml`/`.yaml` changes outside `.github/`.

### [`terraform-lint.yml`](terraform-lint.yml)
Runs `terraform fmt -check`, `terraform validate`, and [TFLint](https://github.com/terraform-linters/tflint) (with the AWS ruleset) on push and PR. Scoped to `.tf` changes. Includes a commented-out `terraform plan` job that requires OIDC federation for AWS credentials.

### [`typescript-lint.yml`](typescript-lint.yml)
Runs [ESLint](https://eslint.org/) with `@typescript-eslint` on CDK stack files (`*-stack.ts`) on push and PR. Syntax-level only — no type-aware checks since CDK directories lack `tsconfig.json`. Includes a commented-out `cdk synth` + `cfn-lint` job for when per-directory CDK scaffolding is added.

### [`iac-security-scan.yml`](iac-security-scan.yml)
Runs [Checkov](https://www.checkov.io/) across the entire repo on push and PR, scanning both Terraform and CloudFormation. Uploads results as SARIF to the GitHub Security tab. Currently set to `soft_fail: true` — won't block PRs until initial findings are triaged.

### [`code-scanning-counter.yml`](code-scanning-counter.yml)
Runs daily (and on manual dispatch) to count open code-scanning alerts via the GitHub API. Writes a shields.io-compatible JSON badge to `.github/badges/code-scanning.json` and commits it back to `main`.

## Covered directories

All lint workflows run against the same matrix of IaC directories:

- `static-website-codepipeline`
- `static-website-scaffolding`
- `visit-counter`
- `daily-stock-checker`
- `ping-me`
