# House Data Simulator

Simulates home IoT devices: camera streaming to Kinesis Video Streams, temperature sensors sending data to Kinesis Firehose, a weather API service, and a smart heater MCP server using ECS Express.

## Project Structure

```
simulate-house/
├── camera-simulator/       # Video streaming container (KVS)
│   ├── Dockerfile
│   ├── stream.sh          # Main streaming logic with credential refresh
│   ├── get-credentials.sh # Fetches ECS credentials at startup
│   └── kvs_log_configuration # Log4cplus config for KVS SDK
├── temperature-simulator/  # Telemetry data generator (Firehose)
│   ├── Dockerfile
│   ├── telemetry.py
│   └── requirements.txt
├── weather-service/        # Weather API service (ECS Express)
│   ├── Dockerfile
│   ├── main.py            # FastAPI application
│   └── requirements.txt
├── heater-service/         # Smart heater MCP server (ECS Express)
│   ├── Dockerfile
│   ├── server.py          # FastMCP server with heater tools
│   └── requirements.txt
├── template.yaml          # CloudFormation infrastructure
└── Makefile              # Build and deployment automation
```

## Architecture

**Camera Simulator**: Streams video to Kinesis Video Streams (stream: "backyard")
**Temperature Simulator**: Generates telemetry for 3 rooms (kitchen, livingroom, bedroom) → Kinesis Firehose → S3 → Glue/Athena
**Weather API**: FastAPI service deployed with ECS Express (automatic ALB, auto-scaling)
**Heater MCP Server**: FastMCP server providing tools to control heater setpoint and query consumption data

**Infrastructure**:
- ECS Fargate with 4 services (camera/telemetry: ARM64/Graviton, weather/heater: x86)
- VPC with 2 AZs and public subnets
- S3 bucket for telemetry storage
- Glue database for Athena queries with partition projection
- KVS stream with 7-day retention
- Application Load Balancers (auto-provisioned by ECS Express for weather/heater)

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

### Use Weather API

The weather service is deployed with ECS Express and automatically gets a public ALB endpoint. **Authentication required via API key.**

```bash
# Get the ALB endpoint and API key from stack outputs
make outputs

# Query weather (replace <ALB-URL> and <API-KEY> with actual values)
curl -X POST https://<ALB-URL>/weather \
  -H "Content-Type: application/json" \
  -H "X-API-Key: <API-KEY>" \
  -d '{"location": "Stockholm"}'

# Response:
# {
#   "location": "Stockholm",
#   "temperature": -7.3,
#   "description": "Sunny and clear skies"
# }

# Temperature is randomized between -10 and -4°C
# API key is automatically generated and shown in stack outputs

# View OpenAPI spec
curl https://<ALB-URL>/docs
```

### Use Heater MCP Server

The heater service is an MCP (Model Context Protocol) server deployed with ECS Express. It provides three tools for controlling and monitoring the smart heater.

**Available Tools:**
- `get_setpoint()` - Get current heater target temperature
- `modify_setpoint(temperature: int)` - Set heater temperature (8-25°C)
- `get_consumption(days: int)` - Get energy consumption history (1-365 days)

**Example with FastMCP Client:**

```python
from fastmcp import FastMCP

# Get the heater MCP endpoint from stack outputs
# No authentication required for MCP servers

async def control_heater():
    # Connect to MCP server
    async with FastMCP.connect_http("https://<HEATER-ALB-URL>/mcp") as client:
        # Get current setpoint
        result = await client.call_tool("get_setpoint")
        print(f"Current setpoint: {result['setpoint']}°C")

        # Update setpoint
        result = await client.call_tool("modify_setpoint", temperature=22)
        print(f"Updated from {result['previous_setpoint']}°C to {result['new_setpoint']}°C")

        # Get 7-day consumption history
        result = await client.call_tool("get_consumption", days=7)
        print(f"Total consumption: {result['total_kwh']} kWh")
        print(f"Average per day: {result['average_kwh_per_day']} kWh")
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
make push-weather-service
make push-heater-service
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
- **Weather API**: 0.25 vCPU, 512 MB RAM (ECS Express)
- **Heater MCP**: 0.25 vCPU, 512 MB RAM (ECS Express)
- **Video retention**: 7 days
- **Firehose interval**: 3 minutes

## Troubleshooting

**Docker permission denied**: Run `newgrp docker` or log out/in
**Build fails**: Ensure sufficient disk space and ARM64 platform
**Deployment fails**: Check `aws cloudformation describe-stack-events --stack-name house-simulator`
