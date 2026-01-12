provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  # The "Magic" Switch: Redirecting AWS calls to LocalStack [cite: 56]
  endpoints {
    sns      = "http://localhost:4566"
    sqs      = "http://localhost:4566"
    lambda   = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
    iam      = "http://localhost:4566"
    sts      = "http://localhost:4566" 
  }
}

# 1. The Entry Point: SNS Topic (The "Announcer")
resource "aws_sns_topic" "delivery_updates" {
  name = "driver-delivery-updates"
}

# 2. The Dead Letter Queue (The "Safety Net")
# If a message fails processing 3 times, it goes here so we don't lose it
resource "aws_sqs_queue" "delivery_dlq" {
  name = "delivery-processing-dlq"
}

# 3. The Main Processing Queue (The "Worker")
resource "aws_sqs_queue" "delivery_queue" {
  name = "delivery-processing-queue"

  # The Redrive Policy is critical for resilience
  # It links this queue to the DLQ defined above.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.delivery_dlq.arn
    maxReceiveCount     = 3
  })
}

# 4. Subscribe Queue to SNS (The "Connection")
# This creates the "Fan-Out" - SNS pushes to SQS
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.delivery_updates.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.delivery_queue.arn
}

# 5. The Database
resource "aws_dynamodb_table" "deliveries" {
  name           = "Savannah-Deliveries"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

# 6. Zip the Python code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda/processor.py"
  output_path = "lambda/processor.zip"
}

# 7. The Lambda Function
resource "aws_lambda_function" "processor" {
  filename      = "lambda/processor.zip"
  function_name = "DeliveryProcessor"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "processor.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables help code portability
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.deliveries.name
    }
  }
}

# 8. IAM Role (Basic Permissions)
# In real AWS, we would limit this. In LocalStack, we can use a basic assume role.
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 9. Trigger Lambda from SQS (The "Mapping")
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.delivery_queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 5 # Process 5 orders at a time [cite: 162]
}
