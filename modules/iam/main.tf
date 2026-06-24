terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "name" {
  type = string
}

variable "s3_bucket_arn" {
  description = "ARN of the bucket the EC2 role is allowed to read from"
  type        = string
}

# Trust policy: only the EC2 service can assume this role.
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Least-privilege: read-only on the one bucket this app needs, not S3:* on *.
data "aws_iam_policy_document" "s3_read_only" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.s3_bucket_arn]
  }

  statement {
    sid       = "ReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "s3_read_only" {
  name   = "${var.name}-s3-read-only"
  policy = data.aws_iam_policy_document.s3_read_only.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_only.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

output "role_name" {
  value = aws_iam_role.ec2_role.name
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}
