# ============================================================================
# S3 CROSS-REGION REPLICATION (primary → secondary)
#
# Three pieces must exist before replication works:
#   1. Both source and destination buckets have versioning ENABLED.
#   2. An IAM role that S3 can assume to read source objects and write
#      to the destination.
#   3. A replication configuration on the source bucket referencing 1 & 2.
#
# The s3 module (primary) already enables versioning.
# The s3-replica module (secondary) also enables versioning.
# This file owns the IAM role + replication config that links them.
# ============================================================================

# ── IAM role S3 uses to replicate ─────────────────────────────────────────────

data "aws_iam_policy_document" "replication_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.project_name}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_trust.json
}

data "aws_iam_policy_document" "replication_perms" {
  # Read the replication configuration from the source bucket itself
  statement {
    sid     = "SourceBucketMeta"
    effect  = "Allow"
    actions = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [module.s3.bucket_arn]
  }

  # Read versioned objects from the source
  statement {
    sid    = "SourceObjectRead"
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${module.s3.bucket_arn}/*"]
  }

  # Write replicated objects to the destination
  statement {
    sid    = "DestinationWrite"
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${module.s3_replica.bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${var.project_name}-s3-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication_perms.json
}

# ── Replication configuration on the source bucket ────────────────────────────
# "replicate-all" copies every object; you could add a `filter {}` block to
# scope replication to a specific key prefix or tag.

resource "aws_s3_bucket_replication_configuration" "primary_to_replica" {
  bucket = module.s3.bucket_id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = module.s3_replica.bucket_arn
      storage_class = "STANDARD"
    }
  }
}
