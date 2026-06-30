terraform {
  required_providers {
    aws     = { source = "hashicorp/aws" }
    archive = { source = "hashicorp/archive" }
  }
}

variable "name" {
  type = string
}

variable "s3_bucket_id" {
  description = "ID (name) of the S3 bucket this Lambda will read from"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket that will invoke this Lambda"
  type        = string
}

# ── IAM: trust + permissions ──────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  name               = "${var.name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "perms" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid       = "S3Read"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "perms" {
  name   = "${var.name}-lambda-perms"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.perms.json
}

# ── Package the handler ────────────────────────────────────────────────────────
# archive_file zips handler.py at plan time so Terraform can detect source
# changes via source_code_hash and redeploy automatically.

data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/handler.zip"
}

# ── Lambda function ────────────────────────────────────────────────────────────

resource "aws_lambda_function" "this" {
  function_name    = "${var.name}-s3-event-handler"
  role             = aws_iam_role.exec.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = var.s3_bucket_id
    }
  }

  tags = {
    Name = "${var.name}-s3-event-handler"
  }
}

# ── Allow S3 to invoke this function ──────────────────────────────────────────
# Without this resource-based policy, S3 can't call lambda:InvokeFunction
# even though the bucket notification is wired up.

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "function_name" {
  value = aws_lambda_function.this.function_name
}
