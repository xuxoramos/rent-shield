#!/bin/sh
set -e

# --- Simple process supervisor: restart background services if they die ---
supervise() {
    name="$1"; shift
    while true; do
        echo "[supervisor] starting $name"
        "$@" || true
        echo "[supervisor] $name exited, restarting in 2s..."
        sleep 2
    done
}

# --- Wait for a service to be ready on a given port ---
wait_for() {
    name="$1"; port="$2"; max="$3"
    echo "[readiness] waiting for $name on port $port (max ${max}s)..."
    elapsed=0
    while [ "$elapsed" -lt "$max" ]; do
        if wget -qO /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then
            echo "[readiness] $name is ready (${elapsed}s)"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "[readiness] WARNING: $name not ready after ${max}s — continuing anyway"
    return 0
}

# Start FastAPI (supervised, background)
# Two workers fit comfortably on an 8 GB VPS (~150-200 MB each).
supervise uvicorn uvicorn renter_shield.api:app \
    --host 0.0.0.0 --port 8000 \
    --workers 2 \
    --log-level info &

# Start renter Streamlit (supervised, background)
# --server.fileWatcherType none  disables inotify watcher (saves memory in prod)
# --server.maxMessageSize 200    caps WebSocket message at 200 MB
supervise renter-streamlit streamlit run streamlit_renter.py \
    --server.port 8501 \
    --server.address 0.0.0.0 \
    --server.headless true \
    --server.fileWatcherType none \
    --server.maxMessageSize 200 \
    --server.baseUrlPath renter \
    --browser.gatherUsageStats false &

# --- Wait for all services before accepting traffic ---
wait_for "FastAPI"                8000 60
wait_for "Renter Streamlit"       8501 90

# Start investigator Streamlit (supervised, background)
supervise investigator-streamlit streamlit run streamlit_investigator.py \
    --server.port 8502 \
    --server.address 0.0.0.0 \
    --server.headless true \
    --server.fileWatcherType none \
    --server.maxMessageSize 200 \
    --server.baseUrlPath investigator \
    --browser.gatherUsageStats false &

wait_for "Investigator Streamlit" 8502 90
echo "[readiness] all services ready"

# Keep container alive — wait on all background jobs
wait
