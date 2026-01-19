# Savannah Logistics: Event-Driven Delivery Pipeline 🚚

![Architecture Status](https://img.shields.io/badge/Architecture-Event--Driven-orange)
![Stack](https://img.shields.io/badge/Tech-LocalStack%20%7C%20Terraform%20%7C%20Python-blue)

> **A rigorous architectural case study moving a monolithic "Friday Night Crash" system to a resilient, asynchronous Serverless architecture.**

---

## 💼 The Business Case

**Client:** Savannah Logistics, a Nairobi-based last-mile delivery startup.
**Problem:** The "Friday Night Crash."
During peak windows (Friday evenings), 5,000 drivers upload proof-of-delivery photos simultaneously. The legacy system wrote these updates directly to a PostgreSQL database synchronously.

**Failure Mode:**
* Database locs up under write-heavy load.
* API latency spikes to 30s+ causing timeouts.
* **Business Impact:** Lost transaction data and unpaid drivers.

**The Goal:**
Re-architect the ingestion layer to handle **5,000 concurrent requests** with zero data loss, ensuring the driver app remains responsive (sub-200ms) regardless of database load.

---

## 🏗️ The Solution Architecture

I implemented an **Asynchronous Fan-Out Architecture** using the AWS standard trifecta: SNS, SQS, and Lambda.

### High-Level Data Flow
1. **Ingest:** Driver App posts update to **SNS Topic** (The "Announcer").
2. **Buffer:** SNS fans out to **SQS Queue** (The "Shock Absorber").
3. **Process:** Lambda consumes messages from SQS.
4. **Persist:** Lambda writes to **DynamoDB** with Idempotency checks.
5. **Fail-Safe:** Malformed messages are routed to a **Dead Letter Queue (DLQ)**.

![Architecture](https://github.com/kariukikinyanjui/savannah-logistics/blob/main/screenshots/architecture-diagram.png)

---

## 🧠 Architectural Decision Records (ADRs)

### 1. Decoupling with SQS (The Buffer)
* **Decision:** Decouple the Ingestion API from the Database using SQS.
* **Why:** The Database cannot handle burst traffic. SQS acts as a buffer, smoothing out the "blast radius" of Friday traffic.

### 2. Fan-Out Pattern with SNS
* **Decision:** Publish to *SNS* first, not directly to SQS.
* **Why:** Future-proofing. If the Data Science team needs real-time route analysis later, I can simply subscribe a second queue to this SNS topic without rewriting the Driver App Code.

### 3. Idempotency (Data Integrity)
* **Decision:** Use `attribute_not_exists(order_id)` conditional writes in DynamoDB.
* **Why:** In distributed systems, retries are inevitable. Without idempotency, a network glitch could cause a driver to be paid twice for the same delivery. *This logic ensures strict exactly-once processing*.

### 4. Resilience via Dead Letter Queue (DLQ)
* **Decision:** Configure a Redrive Policy with `maxReceiveCount = 3`.
* **Why:** "Poison pill" messages (malformed *JSON*) shouldn't crash the system or block valid orders. 3 failed attempts, they are moved to a DLQ for manual inspection.

---

## 🛠️ Technology Stack

* **Infrastructure:** Terraform (IaC)
* **Cloud Simulation:** LocalStack Pro
* **Compute:** AWS Lambda (Python 3.9)
* **Messaging:** Amazon SNS & SQS
* **Database:** Amazon DynamoDB

---

## 🚀 How to Run the Simulation

This project simulates a full AWS environment locally using Docker and LocalStack.

### Prerequisites
* Docker & Docker Compose
* Terraform
* AWS CLI (configured with `awslocal` alias)

### 1. Start the Environment
```bash
docker-compose up -d
```
### 2.  Deploy Infrastructure
```bash
terraform init
terraform apply --auto-approve
```

### 3. Inject Events (The Simulation)
**Scenario A:** Simulate a valid driver update.
```bash
awslocal sns publish \
    --topic-arn arn:aws:sns:us-east-1:000000000000:driver-delivery-updates \
    --message '{"order_id": "ORD-101", "driver_id": "DRV-50", "amount": 500}'
```

**Scenario B: The Idempotency Test** Run the command above *TWICE*. The second attempt will be gracefully skipped. Proof:
![Idempotency](https://github.com/kariukikinyanjui/savannah-logistics/blob/main/screenshots/idempotency.png)

**Scenario C: The Failure Mode** Inject a "Poison Pill" (bad *JSON*).
```bash
awslocal sns publish \
    --topic-arn arn:aws:sns:us-east-1:000000000000:driver-delivery-updates \
    --message 'THIS_IS_NOT_JSON'
```
Result: Message moves to DLQ after 3 retries.

## 💰 Cost Analysis (Estimated)
Comparison for a workload of **1 Million Requests/Month:**

**Architecture**             | **Component**                   | **Est. Cost** |
-----------------------------|---------------------------------|---------------|
**Traditional (EC2)**        | 2x t3.medium (Load Balanced)    | ~$80.00/mo    |
**Serverless (This Project** | Lambda + SQS + SNS (Pay-per-use)|**~$5.00/mo**  |

**Conclusion:** The Serverless approach is ~94% cheaper for this specific startup workload.

## 📈 Future Improvements
* Add CloudWatch Alarms for DLQ depth (alerting engineers when failures occur).
* Implement a replay script to "redrive" messages from the DLQ back to the main queue after fixing the bug.
