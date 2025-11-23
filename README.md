# House Data Simulator

Simulates home IoT devices: camera streaming to Kinesis Video Streams and temperature sensors sending data to Kinesis Firehose for analytics.

## Project Structure

```
simulate-house/
├── camera-simulator/       # Video streaming container (KVS)
│   ├── Dockerfile
│   ├── stream.sh
│   └── get-credentials.sh
├── temperature-simulator/  # Telemetry data generator (Firehose)
│   ├── Dockerfile
│   └── telemetry.py
├── template.yaml          # CloudFormation infrastructure
└── Makefile              # Build and deployment automation
```

## Architecture

**Camera Simulator**: Streams video to Kinesis Video Streams (stream: "backyard")
**Temperature Simulator**: Generates telemetry for 3 rooms (kitchen, livingroom, bedroom) → Kinesis Firehose → S3 → Glue/Athena

**Infrastructure**:
- ECS Fargate (ARM64/Graviton) with 2 services in public subnets
- VPC with 2 AZs
- S3 bucket for telemetry storage
- Glue database for Athena queries with partition projection
- KVS stream with 7-day retention

## Quick Start

### Prerequisites
- AWS account with CLI configured
- Docker installed
- ARM64 machine recommended (or use `--platform` for cross-compilation)

### Deploy

```bash
# Clone repository
git clone <your-repo-url>
cd simulate-house

# Deploy everything (builds, pushes, deploys)
make all
```

This automatically:
1. Checks dependencies
2. Creates ECS service-linked role if needed
3. Builds Docker images
4. Pushes to ECR
5. Deploys CloudFormation stack

### View Resources

```bash
# Show stack outputs (bucket name, stream name, etc.)
make outputs

# View video stream
# AWS Console → Kinesis Video Streams → backyard
```

### Query Telemetry Data

```sql
SELECT * FROM house_db.temperature_readings
WHERE ingest_date = '2025-11-23'
ORDER BY time_recorded DESC
LIMIT 100;
```

## Configuration

Edit `Makefile`:
- `AWS_REGION` - Target region (default: eu-west-1)
- `STACK_NAME` - Stack name (default: house-simulator)
- `VIDEO_URL` - Video source URL

## Manual Deployment

```bash
make check-deps           # Verify Docker, AWS CLI
make check-ecs-role       # Ensure ECS role exists (first-time only)
make push-camera-simulator
make push-telemetry-simulator
make deploy
```

## Cleanup

```bash
make delete
```

Removes all resources: scales down services, empties S3 bucket, deletes ECR images, and removes CloudFormation stack.

## Resource Allocation

- **Camera**: 2 vCPU, 4 GB RAM
- **Telemetry**: 0.25 vCPU, 512 MB RAM
- **Video retention**: 7 days
- **Firehose interval**: 3 minutes

## Troubleshooting

**Docker permission denied**: Run `newgrp docker` or log out/in
**Build fails**: Ensure sufficient disk space and ARM64 platform
**Deployment fails**: Check `aws cloudformation describe-stack-events --stack-name house-simulator`
