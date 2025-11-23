#!/bin/bash
# Fetch credentials from ECS metadata endpoint and export as environment variables
set -e

if [ -n "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
    echo "Fetching credentials from ECS metadata endpoint..."
    CREDS=$(curl -s "http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}")

    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['AccessKeyId'])")
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['SecretAccessKey'])")
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Token'])")

    echo "Credentials fetched and exported as environment variables"
else
    echo "No ECS metadata endpoint found, using existing credentials"
fi

exec "$@"
