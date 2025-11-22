#!/bin/bash
# Selkies-gstreamer entrypoint script for Coder workspaces
# This script initializes the desktop environment and starts Selkies

set -e

echo "=========================================="
echo "Selkies Desktop Environment Initialization"
echo "=========================================="

# Enable TCP MTU probing to handle MTU 1450 overlay network
# This prevents WebSocket packet fragmentation and retransmissions
echo "Enabling TCP MTU probing..."
if echo 1 > /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null; then
    echo "✓ TCP MTU probing enabled"
else
    echo "⚠ WARNING: Could not enable TCP MTU probing (read-only filesystem)"
    echo "  This may cause WebSocket issues on MTU 1450 networks"
    echo "  Consider adding securityContext.sysctls to pod spec"
fi

# Function to wait for a service
wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=${3:-60}
    local attempt=0

    echo "Waiting for $service on port $port..."
    while ! nc -z localhost $port 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "ERROR: $service failed to start after $max_attempts attempts"
            return 1
        fi
        sleep 1
    done
    echo "✓ $service is ready on port $port"
    return 0
}

# Set up environment variables
export USER=${USER:-coder}
export HOME=${HOME:-/home/$USER}
export DISPLAY=${DISPLAY:-:0}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/var/run/user/$(id -u)}
export PULSE_RUNTIME_PATH=${PULSE_RUNTIME_PATH:-/tmp/pulse}

# Ensure XDG runtime directory exists with correct permissions
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown $(id -u):$(id -g) "$XDG_RUNTIME_DIR"
    sudo chmod 700 "$XDG_RUNTIME_DIR"
fi

# Create necessary directories
mkdir -p ~/.config ~/.local/share ~/.cache
mkdir -p "$PULSE_RUNTIME_PATH"

# Configure display resolution if provided
if [ -n "$SELKIES_DISPLAY_SIZEW" ] && [ -n "$SELKIES_DISPLAY_SIZEH" ]; then
    export RESOLUTION="${SELKIES_DISPLAY_SIZEW}x${SELKIES_DISPLAY_SIZEH}"
else
    export RESOLUTION="${RESOLUTION:-1920x1080}"
fi

# Configure refresh rate
export REFRESH_RATE=${SELKIES_DISPLAY_REFRESH:-60}

# Start D-Bus session bus
echo "Starting D-Bus session..."
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    echo "D-Bus session started: $DBUS_SESSION_BUS_ADDRESS"
fi

# Start X11 virtual display
echo "Starting X11 virtual display on $DISPLAY..."
Xvfb $DISPLAY \
    -screen 0 ${RESOLUTION}x24 \
    -ac \
    -pn \
    -noreset \
    +extension GLX \
    +extension RANDR \
    +extension RENDER \
    -nolisten tcp &

# Wait for X11 to be ready
sleep 2
timeout 30 bash -c "until xdpyinfo -display $DISPLAY >/dev/null 2>&1; do sleep 0.5; done"
if [ $? -ne 0 ]; then
    echo "ERROR: X11 server failed to start"
    exit 1
fi
echo "✓ X11 server is running on $DISPLAY"

# Create PulseAudio directories
mkdir -p "$PULSE_RUNTIME_PATH"
mkdir -p ~/.config/pulse

# Start PulseAudio
echo "Starting PulseAudio..."
pulseaudio -D --exit-idle-time=-1 --log-level=info 2>&1 | tee /tmp/pulseaudio.log &
sleep 2

# Check PulseAudio
if pactl info >/dev/null 2>&1; then
    echo "✓ PulseAudio is running"
else
    echo "WARNING: PulseAudio failed to start, audio will not be available"
    echo "Check /tmp/pulseaudio.log for details"
fi

# Start XFCE desktop environment
echo "Starting XFCE desktop environment..."
xfce4-session --display=$DISPLAY &
XFCE_PID=$!

# Wait for XFCE to initialize
sleep 5

# Configure display settings
if command -v xrandr >/dev/null 2>&1; then
    echo "Configuring display settings..."
    xrandr --display $DISPLAY --output screen --mode $RESOLUTION --rate $REFRESH_RATE 2>/dev/null || true
fi

# Start Selkies-gstreamer
echo "Starting Selkies-gstreamer..."

# Set Selkies environment variables
export SELKIES_ENCODER=${SELKIES_ENCODER:-x264enc}
export SELKIES_ENABLE_RESIZE=${SELKIES_ENABLE_RESIZE:-true}
export SELKIES_ENABLE_AUDIO=${SELKIES_ENABLE_AUDIO:-true}
export SELKIES_PORT=${SELKIES_PORT:-8080}
export SELKIES_METRICS_PORT=${SELKIES_METRICS_PORT:-9090}

# Configure video quality based on available CPU
if [ -z "$SELKIES_VIDEO_BITRATE" ]; then
    CPU_COUNT=$(nproc)
    if [ $CPU_COUNT -ge 8 ]; then
        export SELKIES_VIDEO_BITRATE=8000000  # 8 Mbps for high CPU
    elif [ $CPU_COUNT -ge 4 ]; then
        export SELKIES_VIDEO_BITRATE=4000000  # 4 Mbps for medium CPU
    else
        export SELKIES_VIDEO_BITRATE=2000000  # 2 Mbps for low CPU
    fi
    echo "Auto-configured video bitrate: $(($SELKIES_VIDEO_BITRATE / 1000000)) Mbps"
fi

# Configure audio bitrate
export SELKIES_AUDIO_BITRATE=${SELKIES_AUDIO_BITRATE:-128000}

# Configure framerate
export SELKIES_FRAMERATE=${SELKIES_FRAMERATE:-30}

# Wait for TURN credentials from Coder agent (with timeout)
echo "Waiting for TURN credentials from Coder agent..."
TURN_CONFIG_TIMEOUT=30
TURN_CONFIG_WAIT=0
while [ ! -f /tmp/turn-config.json ] && [ $TURN_CONFIG_WAIT -lt $TURN_CONFIG_TIMEOUT ]; do
    sleep 1
    TURN_CONFIG_WAIT=$((TURN_CONFIG_WAIT + 1))
done

# Load TURN credentials if available (written by Coder agent)
if [ -f /tmp/turn-config.json ]; then
    SELKIES_RTC_CONFIG_JSON=$(cat /tmp/turn-config.json)
    echo "✓ Loaded TURN credentials from Coder agent"
else
    SELKIES_RTC_CONFIG_JSON='{"iceServers":[],"iceTransportPolicy":"all"}'
    echo "⚠ TURN config not found after ${TURN_CONFIG_TIMEOUT}s, using default STUN only"
fi

# Verify Selkies is installed (check Python module)
if ! python3 -c "import selkies_gstreamer" 2>/dev/null; then
    echo "ERROR: selkies_gstreamer module not found!"
    echo "Available Python packages:"
    pip3 list | grep -i selkies
    echo "Python path:"
    python3 -c "import sys; print('\\n'.join(sys.path))"
    exit 1
fi
echo "✓ selkies_gstreamer Python module found"

# Start Selkies signaling server (internal port 8081)
echo "Starting Selkies signaling server on port 8081..."

# Source GStreamer environment (sets GST_PLUGIN_PATH, LD_LIBRARY_PATH, etc.)
if [ -f /opt/gstreamer/gst-env ]; then
    source /opt/gstreamer/gst-env
    echo "✓ GStreamer environment sourced from /opt/gstreamer/gst-env"
    echo "  GST_PLUGIN_PATH: $GST_PLUGIN_PATH"
else
    echo "WARNING: /opt/gstreamer/gst-env not found - GStreamer plugins may not load!"
fi

# Verify selkies-gstreamer binary exists
if ! command -v selkies-gstreamer >/dev/null 2>&1; then
    echo "ERROR: selkies-gstreamer binary not found in PATH!"
    echo "Available Python packages:"
    pip3 list | grep -i selkies
    exit 1
fi

# Start Selkies with proper binary and flags (serves static files + WebSocket directly)
# No NGINX needed - Selkies serves everything like websockify does in arch-i3
export SELKIES_PORT=8080
export SELKIES_CONTROL_PORT=8082
SELKIES_RTC_CONFIG_JSON="$SELKIES_RTC_CONFIG_JSON" selkies-gstreamer \
    --addr="localhost" \
    --port="8080" \
    --web_root="/opt/gst-web" \
    --enable_basic_auth="false" \
    --enable_metrics_http="true" \
    --metrics_http_port="9081" \
    2>&1 | tee /tmp/selkies.log &

SELKIES_PID=$!
echo "Selkies PID: $SELKIES_PID"

# Wait for Selkies web server to be ready (port 8080)
wait_for_service "Selkies Web Server" 8080 60

# If running with Coder agent, download and start it now
if [ -n "$CODER_AGENT_TOKEN" ]; then
    echo "==========================================  "
    echo "Starting Coder Agent Integration"
    echo "=========================================="

    # Execute init script to set environment variables
    if [ -n "$CODER_AGENT_INIT_SCRIPT" ]; then
        eval "$CODER_AGENT_INIT_SCRIPT"
    fi

    # Download Coder agent binary
    echo "Downloading Coder agent from: $CODER_AGENT_URL"
    if curl -fsSL "$CODER_AGENT_URL/bin/coder-linux-$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')" -o /tmp/coder; then
        chmod +x /tmp/coder
        echo "✓ Coder agent downloaded successfully"

        # Start Coder agent in background as subprocess
        /tmp/coder agent &
        CODER_PID=$!
        echo "✓ Coder agent started (PID: $CODER_PID)"
        echo "  Connecting to: $CODER_AGENT_URL"
    else
        echo "⚠ Failed to download Coder agent from $CODER_AGENT_URL"
        echo "  Continuing without Coder integration..."
    fi
else
    echo "Running in standalone mode (no Coder integration)"
fi

echo ""
echo "=========================================="
echo "✓ Selkies Desktop Environment is Ready!"
echo "=========================================="
echo "Access the desktop at: http://localhost:8080"
echo "Display: $DISPLAY @ $RESOLUTION"
echo "Video Encoder: $SELKIES_ENCODER"
echo "Video Bitrate: $(($SELKIES_VIDEO_BITRATE / 1000000)) Mbps"
echo "Audio Enabled: $SELKIES_ENABLE_AUDIO"
echo "Architecture: Direct (Selkies serves on port 8080)"
echo "=========================================="
echo ""

# Keep the container running
echo "Container is running. Press Ctrl+C to stop..."

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down services..."

    # Kill Coder agent
    if [ -n "$CODER_PID" ]; then
        echo "Stopping Coder agent..."
        kill $CODER_PID 2>/dev/null || true
    fi

    # Kill Selkies
    if [ -n "$SELKIES_PID" ]; then
        echo "Stopping Selkies..."
        kill $SELKIES_PID 2>/dev/null || true
    fi

    # Kill XFCE
    if [ -n "$XFCE_PID" ]; then
        echo "Stopping XFCE..."
        kill $XFCE_PID 2>/dev/null || true
    fi

    # Stop PulseAudio
    echo "Stopping PulseAudio..."
    pulseaudio --kill 2>/dev/null || true

    # Kill X server
    echo "Stopping X server..."
    pkill -f "Xvfb $DISPLAY" 2>/dev/null || true

    echo "Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Wait for Selkies process (keeps container alive)
wait $SELKIES_PID