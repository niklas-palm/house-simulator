#!/usr/bin/env python3
import json
import time
import random
import os
from datetime import datetime, timezone
import boto3

# Environment variables (set by ECS task definition)
DELIVERY_STREAM_NAME = os.environ['DELIVERY_STREAM_NAME']
AWS_REGION = os.environ['AWS_REGION']

# Initialize Firehose client
firehose = boto3.client('firehose', region_name=AWS_REGION)

# Room configurations with baseline temperature and humidity
ROOMS = {
    'kitchen': {'temp_base': 22.0, 'humidity_base': 50},
    'livingroom': {'temp_base': 21.5, 'humidity_base': 48},
    'bedroom': {'temp_base': 20.0, 'humidity_base': 52}
}

def generate_telemetry(room_name, config):
    """Generate realistic temperature and humidity readings with small variations"""
    temperature = round(config['temp_base'] + random.uniform(-2.0, 2.0), 1)
    humidity = round(config['humidity_base'] + random.uniform(-5, 5), 1)

    return {
        'room': room_name,
        'temperature': temperature,
        'humidity': humidity,
        'time_recorded': datetime.now(timezone.utc).isoformat()
    }

def send_to_firehose(record):
    """Send a single record to Kinesis Firehose"""
    try:
        response = firehose.put_record(
            DeliveryStreamName=DELIVERY_STREAM_NAME,
            Record={'Data': json.dumps(record) + '\n'}
        )
        return response['RecordId']
    except Exception as e:
        print(f"Error sending to Firehose: {e}")
        return None

def main():
    print("===================================")
    print("Temperature Telemetry Simulator")
    print("===================================")
    print(f"Delivery Stream: {DELIVERY_STREAM_NAME}")
    print(f"Region: {AWS_REGION}")
    print(f"Rooms: {', '.join(ROOMS.keys())}")
    print(f"Interval: 30 seconds")
    print("===================================")

    while True:
        for room_name, config in ROOMS.items():
            # Generate telemetry data
            telemetry = generate_telemetry(room_name, config)

            # Send to Firehose
            record_id = send_to_firehose(telemetry)

            if record_id:
                print(f"[{telemetry['time_recorded']}] {room_name}: "
                      f"{telemetry['temperature']}°C, {telemetry['humidity']}% "
                      f"(RecordId: {record_id})")
            else:
                print(f"[{telemetry['time_recorded']}] Failed to send data for {room_name}")

        # Wait 30 seconds before next batch
        time.sleep(30)

if __name__ == '__main__':
    main()
