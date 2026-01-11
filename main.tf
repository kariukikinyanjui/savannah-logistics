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
