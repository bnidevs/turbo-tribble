import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as codepipeline from "aws-cdk-lib/aws-codepipeline";
import * as codepipeline_actions from "aws-cdk-lib/aws-codepipeline-actions";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as lambda from "aws-cdk-lib/aws-lambda";

interface StaticSitePipelineStackProps extends cdk.StackProps {
  codestarConnectionArn: string;
  stagingBucketName: string;
  prodBucketName: string;
  addCacheControlHeaderFunctionArn: string;
  invalidateCloudFrontDistroFunctionArn: string;
}

export class StaticSitePipelineStack extends cdk.Stack {
  constructor(
    scope: Construct,
    id: string,
    props: StaticSitePipelineStackProps
  ) {
    super(scope, id, props);

    // ── Look up existing resources ──────────────────────────────────────────

    const stagingBucket = s3.Bucket.fromBucketName(
      this,
      "StagingBucket",
      props.stagingBucketName
    );

    const prodBucket = s3.Bucket.fromBucketName(
      this,
      "ProdBucket",
      props.prodBucketName
    );

    const addCacheControlFn = lambda.Function.fromFunctionArn(
      this,
      "AddCacheControlHeaderFn",
      props.addCacheControlHeaderFunctionArn
    );

    const invalidateCfFn = lambda.Function.fromFunctionArn(
      this,
      "InvalidateCloudFrontDistroFn",
      props.invalidateCloudFrontDistroFunctionArn
    );

    // ── Artifacts ───────────────────────────────────────────────────────────

    const sourceOutput = new codepipeline.Artifact("source_output");

    // ── Pipeline ────────────────────────────────────────────────────────────

    const pipeline = new codepipeline.Pipeline(this, "StaticSitePipeline", {
      pipelineName: "static-site-pipeline",
      restartExecutionOnUpdate: false,
    });

    // Stage 1: Source
    pipeline.addStage({
      stageName: "Source",
      actions: [
        new codepipeline_actions.CodeStarConnectionsSourceAction({
          actionName: "Source",
          connectionArn: props.codestarConnectionArn,
          owner: "your-org",
          repo: "your-repo",
          branch: "main",
          output: sourceOutput,
        }),
      ],
    });

    // Stage 2: Alpha (staging deploy)
    pipeline.addStage({
      stageName: "Alpha",
      actions: [
        new codepipeline_actions.S3DeployAction({
          actionName: "Deploy",
          bucket: stagingBucket,
          input: sourceOutput,
          extract: true,
        }),
      ],
    });

    // Stage 3: Approval
    pipeline.addStage({
      stageName: "Approval",
      actions: [
        new codepipeline_actions.ManualApprovalAction({
          actionName: "Manual_Approval",
        }),
      ],
    });

    // Stage 4: Deploy (production)
    pipeline.addStage({
      stageName: "Deploy",
      actions: [
        new codepipeline_actions.S3DeployAction({
          actionName: "Deploy",
          bucket: prodBucket,
          input: sourceOutput,
          extract: true,
        }),
      ],
    });

    // Stage 5: Cleanup (sequential Lambda invokes)
    pipeline.addStage({
      stageName: "Cleanup",
      actions: [
        new codepipeline_actions.LambdaInvokeAction({
          actionName: "Add_Cache_Control_Header",
          lambda: addCacheControlFn,
          runOrder: 1,
        }),
        new codepipeline_actions.LambdaInvokeAction({
          actionName: "Invalidate-CloudFront-Distro",
          lambda: invalidateCfFn,
          runOrder: 2,
        }),
      ],
    });
  }
}
