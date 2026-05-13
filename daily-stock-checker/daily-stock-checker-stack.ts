#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as sns from "aws-cdk-lib/aws-sns";
import { Construct } from "constructs";
import * as path from "path";

interface DailyStockCheckerStackProps extends cdk.StackProps {
  snsTopicArn: string;
  fmpApiKey: string;
  stockSymbol?: string;
  targetPrice?: number;
}

class DailyStockCheckerStack extends cdk.Stack {
  constructor(
    scope: Construct,
    id: string,
    props: DailyStockCheckerStackProps
  ) {
    super(scope, id, props);

    const {
      snsTopicArn,
      fmpApiKey,
      stockSymbol = "AMZN",
      targetPrice = 300,
    } = props;

    const snsTopic = sns.Topic.fromTopicArn(
      this,
      "StockNotificationTopic",
      snsTopicArn
    );

    const fn = new lambda.Function(this, "StockCheckerFunction", {
      functionName: "daily-stock-checker",
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: "lambda_function.lambda_handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "../lambda")),
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      reservedConcurrentExecutions: 1,
      environment: {
        API_KEY: fmpApiKey,
        STOCK: stockSymbol,
        TARGET: targetPrice.toString(),
        SNS_TOPIC_ARN: snsTopicArn,
      },
    });

    snsTopic.grantPublish(fn);

    const rule = new events.Rule(this, "DailySchedule", {
      ruleName: "daily-stock-checker-schedule",
      description: "Triggers stock checker Lambda Mon-Fri at 5 PM UTC",
      schedule: events.Schedule.cron({
        minute: "0",
        hour: "17",
        weekDay: "MON-FRI",
      }),
    });

    rule.addTarget(new targets.LambdaFunction(fn));
  }
}

const app = new cdk.App();

new DailyStockCheckerStack(app, "DailyStockCheckerStack", {
  snsTopicArn: app.node.tryGetContext("snsTopicArn") || "YOUR_SNS_TOPIC_ARN",
  fmpApiKey: app.node.tryGetContext("fmpApiKey") || "YOUR_API_KEY",
  stockSymbol: app.node.tryGetContext("stockSymbol") || "AMZN",
  targetPrice: Number(app.node.tryGetContext("targetPrice")) || 300,
});
