#!/usr/bin/env python3
import os
import random
from fastapi import FastAPI, Header, HTTPException, Depends
from pydantic import BaseModel

app = FastAPI(title="Weather Service", version="1.0.0")

# Get API key from environment variable
EXPECTED_API_KEY = os.getenv("API_KEY", "")


class WeatherRequest(BaseModel):
    location: str


class WeatherResponse(BaseModel):
    location: str
    temperature: float
    description: str


def verify_api_key(x_api_key: str = Header(...)):
    """Verify the API key from the X-API-Key header"""
    if not EXPECTED_API_KEY:
        raise HTTPException(status_code=500, detail="API key not configured")

    if x_api_key != EXPECTED_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

    return x_api_key


@app.get("/health")
async def health_check():
    """Health check endpoint for ALB (no authentication required)"""
    return {"status": "healthy"}


@app.post("/weather", response_model=WeatherResponse)
async def get_weather(
    request: WeatherRequest,
    api_key: str = Depends(verify_api_key)
):
    """Get weather information for a location (requires API key)"""
    # Generate random temperature between -10 and -4 degrees Celsius
    temperature = round(random.uniform(-10.0, -4.0), 1)

    return WeatherResponse(
        location=request.location,
        temperature=temperature,
        description="Sunny and clear skies",
    )


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "Weather API",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check endpoint",
            "/weather": "POST - Get weather for a location",
        },
    }
