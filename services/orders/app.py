"""Orders service: stores orders in Redis and reserves stock via the inventory service.

Intentionally uninstrumented -- OpenTelemetry is expected to be auto-injected.
"""
import json
import logging
import os
import random
import time
import uuid

import redis
import requests
from flask import Flask, jsonify, request

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("orders")

INVENTORY_URL = os.environ.get("INVENTORY_URL", "http://inventory:8080")
REDIS_HOST = os.environ.get("REDIS_HOST", "redis")

app = Flask(__name__)
db = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/stock")
def stock():
    r = requests.get(f"{INVENTORY_URL}/inventory", timeout=5)
    return jsonify(r.json()), r.status_code


@app.post("/orders")
def create_order():
    body = request.get_json(force=True) or {}
    sku, qty = body.get("sku"), int(body.get("qty", 1))
    if not sku:
        return {"error": "sku required"}, 400

    # Simulated validation work so spans have some width.
    time.sleep(random.uniform(0.005, 0.03))

    r = requests.post(f"{INVENTORY_URL}/inventory/{sku}/reserve", params={"qty": qty}, timeout=5)
    if r.status_code != 200:
        log.warning("reservation failed sku=%s qty=%s status=%s", sku, qty, r.status_code)
        # Pass through client errors (unknown sku / out of stock); anything else is a bad gateway.
        status = r.status_code if r.status_code in (404, 409) else 502
        return {"error": "reservation failed", "inventory": r.json()}, status

    order = {"id": str(uuid.uuid4()), "sku": sku, "qty": qty, "ts": time.time()}
    db.lpush("orders", json.dumps(order))
    db.ltrim("orders", 0, 99)
    log.info("order created id=%s sku=%s qty=%s", order["id"], sku, qty)
    return order, 201


@app.get("/orders")
def list_orders():
    return jsonify([json.loads(o) for o in db.lrange("orders", 0, 19)])


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
