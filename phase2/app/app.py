import os, socket
from datetime import datetime, timezone
from flask import Flask, jsonify
app=Flask(__name__)
@app.get("/")
def index(): return jsonify(application="webhook-dashboard",message="ROSA Phase 2 application is running",hostname=socket.gethostname(),environment=os.getenv("APP_ENV","dev"),timestamp=datetime.now(timezone.utc).isoformat())
@app.get("/healthz")
def health(): return jsonify(status="healthy"),200
@app.get("/readyz")
def ready(): return jsonify(status="ready"),200
