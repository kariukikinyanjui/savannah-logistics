import json
import boto3
import os
from botocore.exceptions import ClientError

# Initialize DynamoDB resource
# Note: 'http://localstack:4566' allows this Docker container to talk to the main LocalStack container.
dynamodb = boto3.resource('dynamodb', endpoint_url="http://localstack:4566", region_name="us-east-1")
table = dynamodb.Table('Savannah-Deliveries') # Matches the corrected Terraform name

def lambda_handler(event, context):
    # Standard SQS event structure contains a list of 'Records'
    for record in event['Records']:
        try:
            # 1. DEEP PARSING
            # SQS wraps the message in 'body'
            payload = json.loads(record['body'])
            # SNS wraps the actual data in 'Message'
            message = json.loads(payload['Message'])

            order_id = message['order_id']
            driver_id = message['driver_id']
            amount = message['amount']

            print(f"Processing Order: {order_id} for Driver: {driver_id}")

            # 2. IDEMPOTENCY CHECK (The Senior Pattern)
            # We attempt to put the item ONLY IF the 'order_id' does not already exist.
            table.put_item(
                Item={
                    'order_id': order_id,
                    'driver_id': driver_id,
                    'status': 'PROCESSED',
                    'amount': amount
                },
                ConditionExpression='attribute_not_exists(order_id)'
            )
            print(f"Success: Order {order_id} processed.")

        except ClientError as e:
            # 3. HANDLING DUPLICATES SAFELY
            if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                print(f"Idempotency Hit: Order {order_id} already processed. Skipping.")
            else:
                # If it's a real error (db down, auth failed), we raise it.
                # This triggers the SQS retry mechanism (eventually moving to DLQ).
                print(f"Error processing record: {e}")
                raise e
        except Exception as e:
            # Catch JSON parsing errors or other unexpected failures
            print(f"Critical Failure: {e}")
            raise e
