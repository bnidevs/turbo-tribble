// =============================================================================
// Static Website Infrastructure
// S3 (public static hosting) → CloudFront → Route 53 + ACM
// =============================================================================
//
// PREREQUISITES:
//   - The domainName context variable must be a domain you own.
//   - After deploying, you must update your domain registrar's nameservers
//     to the ones in the stack outputs.
//   - ACM DNS validation will not complete until the hosted zone is
//     authoritative for the domain (i.e., nameservers are pointed).
//
// USAGE:
//   cdk deploy -c domainName=example.com
// =============================================================================

import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as route53 from "aws-cdk-lib/aws-route53";
import * as targets from "aws-cdk-lib/aws-route53-targets";
import * as acm from "aws-cdk-lib/aws-certificatemanager";
import { Construct } from "constructs";

export class StaticWebsiteStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // Context Variables
    // -------------------------------------------------------------------------

    const domainName = this.node.tryGetContext("domainName");
    if (!domainName) {
      throw new Error(
        'Missing required context variable "domainName". Deploy with: cdk deploy -c domainName=example.com'
      );
    }

    const indexDocument =
      this.node.tryGetContext("indexDocument") ?? "index.html";
    const errorDocument =
      this.node.tryGetContext("errorDocument") ?? "error.html";

    // -------------------------------------------------------------------------
    // S3 Bucket — Public Static Website Hosting
    // -------------------------------------------------------------------------

    const websiteBucket = new s3.Bucket(this, "WebsiteBucket", {
      bucketName: domainName,
      websiteIndexDocument: indexDocument,
      websiteErrorDocument: errorDocument,
      publicReadAccess: true,
      blockPublicAccess: new s3.BlockPublicAccess({
        blockPublicAcls: false,
        blockPublicPolicy: false,
        ignorePublicAcls: false,
        restrictPublicBuckets: false,
      }),
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // -------------------------------------------------------------------------
    // Route 53 Hosted Zone
    // -------------------------------------------------------------------------

    const hostedZone = new route53.PublicHostedZone(this, "HostedZone", {
      zoneName: domainName,
    });

    // -------------------------------------------------------------------------
    // ACM Certificate (us-east-1, required for CloudFront)
    // -------------------------------------------------------------------------
    //
    // DnsValidatedCertificate is deprecated but is the only CDK construct
    // that can create a cert in us-east-1 from a stack deployed to another
    // region AND automatically create the DNS validation record.
    //
    // If your stack deploys to us-east-1, you can use a plain Certificate
    // with DNS validation instead. The deprecated construct still works
    // and is the pragmatic choice for cross-region stacks.
    // -------------------------------------------------------------------------

    const certificate = new acm.DnsValidatedCertificate(
      this,
      "WebsiteCertificate",
      {
        domainName: domainName,
        hostedZone: hostedZone,
        region: "us-east-1",
      }
    );

    // -------------------------------------------------------------------------
    // CloudFront Distribution
    // -------------------------------------------------------------------------

    const distribution = new cloudfront.Distribution(
      this,
      "WebsiteDistribution",
      {
        defaultRootObject: indexDocument,
        domainNames: [domainName],
        certificate: certificate,
        minimumProtocolVersion:
          cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
        priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
        defaultBehavior: {
          // HttpOrigin targets the S3 website endpoint, not the REST endpoint
          origin: new origins.HttpOrigin(
            websiteBucket.bucketWebsiteUrl.replace("http://", ""),
            {
              protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
            }
          ),
          viewerProtocolPolicy:
            cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        },
      }
    );

    // -------------------------------------------------------------------------
    // Route 53 A Record → CloudFront
    // -------------------------------------------------------------------------

    new route53.ARecord(this, "WebsiteARecord", {
      zone: hostedZone,
      recordName: domainName,
      target: route53.RecordTarget.fromAlias(
        new targets.CloudFrontTarget(distribution)
      ),
    });

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, "Nameservers", {
      description: "Update your domain registrar with these nameservers",
      value: cdk.Fn.join(", ", hostedZone.hostedZoneNameServers!),
    });

    new cdk.CfnOutput(this, "CloudFrontDistributionDomain", {
      description: "CloudFront distribution domain name",
      value: distribution.distributionDomainName,
    });

    new cdk.CfnOutput(this, "CloudFrontDistributionId", {
      description:
        "CloudFront distribution ID (needed for cache invalidation)",
      value: distribution.distributionId,
    });

    new cdk.CfnOutput(this, "S3WebsiteEndpoint", {
      description:
        "S3 static website endpoint (publicly accessible — this bypasses CloudFront)",
      value: websiteBucket.bucketWebsiteUrl,
    });

    new cdk.CfnOutput(this, "WebsiteUrl", {
      description: "The live website URL",
      value: `https://${domainName}`,
    });
  }
}
