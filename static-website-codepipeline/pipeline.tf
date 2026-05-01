###############################################################################
# Variables — swap these for your real values
###############################################################################

variable "codestar_connection_arn" {
  description = "ARN of the CodeStar connection to GitHub"
  type        = string
}

variable "staging_bucket" {
  description = "S3 bucket name for the Alpha/staging deploy"
  type        = string
}

variable "prod_bucket" {
  description = "S3 bucket name for the production deploy"
  type        = string
}

variable "add_cache_control_header_function_name" {
  description = "Name of the Lambda that sets Cache-Control headers"
  type        = string
}

variable "invalidate_cloudfront_distro_function_name" {
  description = "Name of the Lambda that invalidates the CloudFront distribution"
  type        = string
}

variable "pipeline_role_arn" {
  description = "IAM role ARN for CodePipeline to assume"
  type        = string
}

###############################################################################
# Artifact store
###############################################################################

resource "aws_s3_bucket" "artifact_store" {
  bucket_prefix = "codepipeline-artifacts-"
  force_destroy = true
}

###############################################################################
# CodePipeline
###############################################################################

resource "aws_codepipeline" "static_site_pipeline" {
  name     = "static-site-pipeline"
  role_arn = var.pipeline_role_arn

  artifact_store {
    location = aws_s3_bucket.artifact_store.bucket
    type     = "S3"
  }

  # ── Stage 1: Source ──────────────────────────────────────────────────────────
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = "your-org/your-repo"
        BranchName       = "main"
      }
    }
  }

  # ── Stage 2: Alpha (staging deploy) ─────────────────────────────────────────
  stage {
    name = "Alpha"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        BucketName = var.staging_bucket
        Extract    = "true"
      }
    }
  }

  # ── Stage 3: Approval ───────────────────────────────────────────────────────
  stage {
    name = "Approval"

    action {
      name     = "Manual_Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  # ── Stage 4: Deploy (production) ────────────────────────────────────────────
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        BucketName = var.prod_bucket
        Extract    = "true"
      }
    }
  }

  # ── Stage 5: Cleanup (sequential Lambda invokes) ────────────────────────────
  stage {
    name = "Cleanup"

    action {
      name             = "Add_Cache_Control_Header"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "Lambda"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      run_order        = 1

      configuration = {
        FunctionName = var.add_cache_control_header_function_name
      }
    }

    action {
      name             = "Invalidate-CloudFront-Distro"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "Lambda"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      run_order        = 2

      configuration = {
        FunctionName = var.invalidate_cloudfront_distro_function_name
      }
    }
  }
}
