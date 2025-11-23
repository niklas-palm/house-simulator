FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy telemetry script
COPY telemetry.py .

# Run the telemetry script
CMD ["python", "telemetry.py"]
