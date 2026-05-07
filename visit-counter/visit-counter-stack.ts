import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as apigateway from "aws-cdk-lib/aws-apigateway";
import * as iam from "aws-cdk-lib/aws-iam";
import * as cr from "aws-cdk-lib/custom-resources";

interface VisitCounterStackProps extends cdk.StackProps {
  tableName?: string;
  allowedOrigin?: string;
}

export class VisitCounterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: VisitCounterStackProps) {
    super(scope, id, props);

    const tableName =
      props?.tableName ?? "bnidevs.github.io-visit-tracker";
    const allowedOrigin =
      props?.allowedOrigin ?? "https://bnidevs.github.io";

    // ---------- DynamoDB Table ----------

    const table = new dynamodb.Table(this, "VisitTracker", {
      tableName,
      partitionKey: { name: "metric", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Seed the counter item so the UpdateExpression doesn't fail on a
    // missing attribute.  AwsCustomResource is idempotent on re-deploy.
    new cr.AwsCustomResource(this, "SeedVisitItem", {
      onCreate: {
        service: "DynamoDB",
        action: "putItem",
        parameters: {
          TableName: table.tableName,
          Item: {
            metric: { S: "visits" },
            amount: { N: "0" },
          },
          ConditionExpression: "attribute_not_exists(metric)",
        },
        physicalResourceId: cr.PhysicalResourceId.of("seed-visits"),
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: [table.tableArn],
      }),
    });

    // ---------- IAM Role for API Gateway → DynamoDB ----------

    const apiRole = new iam.Role(this, "ApiGatewayDynamoRole", {
      assumedBy: new iam.ServicePrincipal("apigateway.amazonaws.com"),
    });

    table.grant(apiRole, "dynamodb:UpdateItem", "dynamodb:GetItem");

    // ---------- API Gateway REST API ----------

    const api = new apigateway.RestApi(this, "VisitCounterApi", {
      restApiName: "visit-counter-api",
      description: `Hit counter for ${allowedOrigin}`,
      deployOptions: { stageName: "prod" },
      defaultCorsPreflightOptions: {
        allowOrigins: [allowedOrigin],
        allowMethods: ["GET", "OPTIONS"],
        allowHeaders: ["Content-Type"],
      },
    });

    const visitResource = api.root.addResource("visit");

    // ----- GET /visit → DynamoDB UpdateItem -----

    const requestTemplate = JSON.stringify({
      TableName: tableName,
      Key: { metric: { S: "visits" } },
      UpdateExpression: "SET amount = amount + :num",
      ExpressionAttributeValues: { ":num": { N: "1" } },
      ReturnValues: "NONE",
    });

    const dynamoIntegration = new apigateway.AwsIntegration({
      service: "dynamodb",
      action: "UpdateItem",
      options: {
        credentialsRole: apiRole,
        requestTemplates: {
          "application/json": requestTemplate,
        },
        integrationResponses: [
          {
            statusCode: "200",
            responseParameters: {
              "method.response.header.Access-Control-Allow-Origin": `'${allowedOrigin}'`,
            },
          },
        ],
      },
    });

    visitResource.addMethod("GET", dynamoIntegration, {
      methodResponses: [
        {
          statusCode: "200",
          responseParameters: {
            "method.response.header.Access-Control-Allow-Origin": true,
          },
        },
      ],
    });

    // ================================================================
    // GET /count → DynamoDB GetItem (returns shields.io badge JSON)
    // ================================================================

    const countResource = api.root.addResource("count");

    const countRequestTemplate = JSON.stringify({
      TableName: tableName,
      Key: { metric: { S: "visits" } },
      ProjectionExpression: "amount",
    });

    const countResponseTemplate = [
      "#set($inputRoot = $input.path('$'))",
      "$inputRoot.Item.amount.N",
    ].join("\n");

    const getItemIntegration = new apigateway.AwsIntegration({
      service: "dynamodb",
      action: "GetItem",
      options: {
        credentialsRole: apiRole,
        requestTemplates: {
          "application/json": countRequestTemplate,
        },
        integrationResponses: [
          {
            statusCode: "200",
            responseTemplates: {
              "application/json": countResponseTemplate,
            },
            responseParameters: {
              "method.response.header.Access-Control-Allow-Origin": `'${allowedOrigin}'`,
            },
          },
        ],
      },
    });

    countResource.addMethod("GET", getItemIntegration, {
      methodResponses: [
        {
          statusCode: "200",
          responseParameters: {
            "method.response.header.Access-Control-Allow-Origin": true,
          },
        },
      ],
    });

    // ---------- Outputs ----------

    new cdk.CfnOutput(this, "InvokeUrl", {
      value: `${api.url}visit`,
    });

    new cdk.CfnOutput(this, "CountUrl", {
      value: `${api.url}count`,
    });
  }
}

// ---------- App entry point ----------

const app = new cdk.App();
new VisitCounterStack(app, "VisitCounterStack", {
  env: {
    region: app.node.tryGetContext("region") ?? "us-east-1",
  },
});
