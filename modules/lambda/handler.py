import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Process S3 ObjectCreated events and log each upload."""
    records = event.get("Records", [])
    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        size = record["s3"]["object"].get("size", 0)
        logger.info(json.dumps({
            "event": "ObjectCreated",
            "bucket": bucket,
            "key": key,
            "size_bytes": size,
        }))
    return {"statusCode": 200, "processed": len(records)}
