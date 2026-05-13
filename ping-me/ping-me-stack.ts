import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as kms from "aws-cdk-lib/aws-kms";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as sns from "aws-cdk-lib/aws-sns";
import * as apigwv2 from "aws-cdk-lib/aws-apigatewayv2";
import * as integrations from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as path from "path";

// ──────────────────────────────────────────────
// Ping-Me: API Gateway HTTP API v2 → Lambda → SNS
// ──────────────────────────────────────────────

interface PingMeStackProps extends cdk.StackProps {
  stageName?: string;
}

export class PingMeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: PingMeStackProps) {
    super(scope, id, props);

    const stageName = props?.stageName ?? "prod";

    // ──── SNS Topic ────

    const topic = new sns.Topic(this, "PingMeTopic", {
      topicName: "ping-me-topic",
      masterKey: kms.Alias.fromAliasName(this, "SnsKey", "alias/aws/sns"),
    });

    // ──── Lambda Function ────

    const fn = new lambda.Function(this, "PingMeFunction", {
      functionName: "ping-me",
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "lambda_function.lambda_handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "../lambda")),
      timeout: cdk.Duration.seconds(10),
      reservedConcurrentExecutions: 2,
      environment: {
        SNS_TOPIC_ARN: topic.topicArn,
      },
    });

    // Grant the Lambda permission to publish to the topic
    topic.grantPublish(fn);

    // ──── API Gateway HTTP API (v2) ────

    const httpApi = new apigwv2.HttpApi(this, "PingMeApi", {
      apiName: "ping-me-api",
    });

    const lambdaIntegration = new integrations.HttpLambdaIntegration(
      "LambdaIntegration",
      fn,
      {
        payloadFormatVersion: apigwv2.PayloadFormatVersion.VERSION_2_0,
      }
    );

    httpApi.addRoutes({
      path: "/ping-me",
      methods: [apigwv2.HttpMethod.GET],
      integration: lambdaIntegration,
    });

    // The default $default stage is created automatically by HttpApi.
    // Add a named stage if you want one in addition:
    new apigwv2.HttpStage(this, "PingMeStage", {
      httpApi,
      stageName,
      autoDeploy: true,
    });

    // ──── Outputs ────

    new cdk.CfnOutput(this, "ApiEndpoint", {
      description: "Public URL for the ping-me endpoint",
      value: `${httpApi.apiEndpoint}/${stageName}/ping-me`,
    });

    new cdk.CfnOutput(this, "SnsTopicArn", {
      description: "ARN of the SNS topic",
      value: topic.topicArn,
    });
  }
}

// ──── App entrypoint ────

const app = new cdk.App();

new PingMeStack(app, "PingMeStack", {
  stageName: "prod",
  env: {
    region: process.env.CDK_DEFAULT_REGION ?? "us-east-1",
    account: process.env.CDK_DEFAULT_ACCOUNT,
  },
});
