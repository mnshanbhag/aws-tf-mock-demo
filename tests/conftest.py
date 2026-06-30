"""
Shared pytest fixtures for LocalStack integration tests.

These values must match what terraform.tfvars.example provisions.
If you change project_name or environment there, update the constants here too.
"""

import pytest
import boto3

LOCALSTACK_URL = "http://localhost:4566"
PRIMARY_REGION = "eu-west-2"
SECONDARY_REGION = "eu-west-1"
PROJECT_NAME = "mits-demo"
ENVIRONMENT = "dev"

_BOTO_KWARGS = dict(
    endpoint_url=LOCALSTACK_URL,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def boto_client(service, region=PRIMARY_REGION):
    return boto3.client(service, region_name=region, **_BOTO_KWARGS)


@pytest.fixture(scope="session")
def primary_bucket_name():
    return f"{PROJECT_NAME}-{ENVIRONMENT}-bucket"


@pytest.fixture(scope="session")
def replica_bucket_name():
    return f"{PROJECT_NAME}-{ENVIRONMENT}-replica"


@pytest.fixture(scope="session")
def lambda_function_name():
    return f"{PROJECT_NAME}-s3-event-handler"


@pytest.fixture(scope="session")
def s3_primary():
    return boto_client("s3", PRIMARY_REGION)


@pytest.fixture(scope="session")
def s3_secondary():
    return boto_client("s3", SECONDARY_REGION)


@pytest.fixture(scope="session")
def lam():
    return boto_client("lambda", PRIMARY_REGION)
