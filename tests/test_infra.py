"""
Integration tests that verify what Terraform actually created in LocalStack.

Prerequisites: LocalStack running + terraform applied.
    make up
    terraform apply -var-file=terraform.tfvars.example
    make test

These tests teach three things:
  1. How to assert bucket configuration (versioning, encryption, access block).
  2. How cross-region replication config looks from the API's perspective.
  3. How to invoke a Lambda directly and via a real S3 upload.
"""

import json
import pytest


# ── S3 primary bucket ──────────────────────────────────────────────────────────

class TestPrimaryBucket:
    def test_bucket_exists(self, s3_primary, primary_bucket_name):
        buckets = [b["Name"] for b in s3_primary.list_buckets()["Buckets"]]
        assert primary_bucket_name in buckets

    def test_versioning_enabled(self, s3_primary, primary_bucket_name):
        v = s3_primary.get_bucket_versioning(Bucket=primary_bucket_name)
        assert v.get("Status") == "Enabled"

    def test_server_side_encryption(self, s3_primary, primary_bucket_name):
        enc = s3_primary.get_bucket_encryption(Bucket=primary_bucket_name)
        rule = enc["ServerSideEncryptionConfiguration"]["Rules"][0]
        algo = rule["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]
        assert algo == "AES256"

    def test_public_access_blocked(self, s3_primary, primary_bucket_name):
        pab = s3_primary.get_public_access_block(Bucket=primary_bucket_name)
        cfg = pab["PublicAccessBlockConfiguration"]
        assert cfg["BlockPublicAcls"] is True
        assert cfg["BlockPublicPolicy"] is True
        assert cfg["IgnorePublicAcls"] is True
        assert cfg["RestrictPublicBuckets"] is True


# ── S3 replica bucket (secondary region) ──────────────────────────────────────

class TestReplicaBucket:
    def test_replica_bucket_exists(self, s3_secondary, replica_bucket_name):
        buckets = [b["Name"] for b in s3_secondary.list_buckets()["Buckets"]]
        assert replica_bucket_name in buckets

    def test_replica_versioning_enabled(self, s3_secondary, replica_bucket_name):
        # Replication requires versioning on both source AND destination.
        v = s3_secondary.get_bucket_versioning(Bucket=replica_bucket_name)
        assert v.get("Status") == "Enabled"


# ── S3 replication configuration ──────────────────────────────────────────────

class TestReplicationConfig:
    def test_replication_rule_exists_and_enabled(self, s3_primary, primary_bucket_name):
        rep = s3_primary.get_bucket_replication(Bucket=primary_bucket_name)
        rules = rep["ReplicationConfiguration"]["Rules"]
        assert len(rules) >= 1
        assert rules[0]["Status"] == "Enabled"

    def test_replication_destination_is_replica_bucket(
        self, s3_primary, primary_bucket_name, replica_bucket_name
    ):
        rep = s3_primary.get_bucket_replication(Bucket=primary_bucket_name)
        dest_arn = rep["ReplicationConfiguration"]["Rules"][0]["Destination"]["Bucket"]
        # ARN format: arn:aws:s3:::bucket-name
        assert dest_arn.endswith(replica_bucket_name)


# ── S3 event notification ─────────────────────────────────────────────────────

class TestEventNotification:
    def test_lambda_notification_configured(self, s3_primary, primary_bucket_name):
        cfg = s3_primary.get_bucket_notification_configuration(Bucket=primary_bucket_name)
        lambdas = cfg.get("LambdaFunctionConfigurations", [])
        assert len(lambdas) >= 1

    def test_notification_triggers_on_object_created(self, s3_primary, primary_bucket_name):
        cfg = s3_primary.get_bucket_notification_configuration(Bucket=primary_bucket_name)
        events = cfg["LambdaFunctionConfigurations"][0]["Events"]
        assert "s3:ObjectCreated:*" in events


# ── Lambda function ────────────────────────────────────────────────────────────

class TestLambda:
    def test_function_exists(self, lam, lambda_function_name):
        fn = lam.get_function(FunctionName=lambda_function_name)
        assert fn["Configuration"]["FunctionName"] == lambda_function_name

    def test_function_runtime(self, lam, lambda_function_name):
        fn = lam.get_function(FunctionName=lambda_function_name)
        assert fn["Configuration"]["Runtime"] == "python3.12"

    def test_direct_invocation_returns_200(self, lam, lambda_function_name, primary_bucket_name):
        """
        Invoke with a synthetic S3 event — the same shape S3 sends when an
        object is uploaded.  Verifies the handler's response contract without
        needing a real upload.
        """
        payload = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": primary_bucket_name},
                        "object": {"key": "test/hello.txt", "size": 11},
                    }
                }
            ]
        }
        response = lam.invoke(
            FunctionName=lambda_function_name,
            Payload=json.dumps(payload).encode(),
        )
        result = json.loads(response["Payload"].read())
        assert result["statusCode"] == 200
        assert result["processed"] == 1

    def test_invocation_with_multiple_records(self, lam, lambda_function_name, primary_bucket_name):
        """Handler must process a batch of events, not just the first one."""
        payload = {
            "Records": [
                {"s3": {"bucket": {"name": primary_bucket_name}, "object": {"key": f"batch/{i}.txt", "size": i}}}
                for i in range(3)
            ]
        }
        response = lam.invoke(
            FunctionName=lambda_function_name,
            Payload=json.dumps(payload).encode(),
        )
        result = json.loads(response["Payload"].read())
        assert result["processed"] == 3


# ── End-to-end upload smoke test ───────────────────────────────────────────────

class TestUploadFlow:
    def test_object_upload_and_retrieval(self, s3_primary, primary_bucket_name):
        """
        Upload an object and read it back — verifies the bucket accepts writes
        and that the notification plumbing doesn't block PutObject.
        """
        key = "integration-test/probe.txt"
        body = b"hello from integration test"

        s3_primary.put_object(Bucket=primary_bucket_name, Key=key, Body=body)
        obj = s3_primary.get_object(Bucket=primary_bucket_name, Key=key)
        assert obj["Body"].read() == body

    def test_uploaded_object_is_versioned(self, s3_primary, primary_bucket_name):
        """Every object in a versioned bucket must have a VersionId."""
        key = "integration-test/versioned.txt"
        put = s3_primary.put_object(Bucket=primary_bucket_name, Key=key, Body=b"v1")
        assert "VersionId" in put
