#!/usr/bin/env python3
import random
from fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse

mcp = FastMCP(
    name="Smart Heater Controller", stateless_http=True  # No session tracking needed
)

# In-memory state
heater_state = {"setpoint": 20}  # Default setpoint in Celsius


# Health check endpoint for ALB
@mcp.custom_route("/health", methods=["GET"])
async def health_check(request: Request) -> JSONResponse:
    return JSONResponse({"status": "healthy"})


@mcp.tool()
def get_setpoint() -> dict:
    """Get the current heater setpoint temperature."""
    return {"setpoint": heater_state["setpoint"], "unit": "celsius"}


@mcp.tool()
def modify_setpoint(temperature: int) -> dict:
    """
    Set heater target temperature.

    Args:
        temperature: Target temperature in Celsius (must be between 8-25)

    Returns:
        Dictionary with previous setpoint, new setpoint, and status
    """
    if not isinstance(temperature, int):
        raise ValueError("Temperature must be an integer")

    if not 8 <= temperature <= 25:
        raise ValueError("Temperature must be between 8 and 25°C")

    old_setpoint = heater_state["setpoint"]
    heater_state["setpoint"] = temperature

    return {
        "previous_setpoint": old_setpoint,
        "new_setpoint": temperature,
        "status": "updated",
        "unit": "celsius",
    }


@mcp.tool()
def get_consumption(days: int) -> dict:
    """
    Get energy consumption for the last N days.

    Args:
        days: Number of days to retrieve consumption for (1-365)

    Returns:
        Dictionary with daily consumption list and total kWh
    """
    if not isinstance(days, int):
        raise ValueError("Days must be an integer")

    if days < 1 or days > 365:
        raise ValueError("Days must be between 1 and 365")

    # Generate consumption based on current setpoint
    setpoint = heater_state["setpoint"]
    daily_consumption = []

    for day in range(1, days + 1):
        # Base consumption on setpoint: higher setpoint = more energy
        base_kwh = setpoint * 1.2
        # Add random variance
        kwh = round(base_kwh + random.uniform(-5, 5), 2)
        # Ensure non-negative
        kwh = max(0, kwh)

        daily_consumption.append({"day": day, "kwh": kwh})

    total_kwh = sum(d["kwh"] for d in daily_consumption)

    return {
        "days": days,
        "daily_consumption": daily_consumption,
        "total_kwh": round(total_kwh, 2),
        "average_kwh_per_day": round(total_kwh / days, 2),
    }


if __name__ == "__main__":
    print("Starting Smart Heater Controller MCP Server...")
    print("MCP Endpoint: http://0.0.0.0:8000/mcp")
    print("Health Check: http://0.0.0.0:8000/health")
    print("=" * 50)

    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp")
