#!/bin/bash
# Selkies-gstreamer entrypoint script for Coder workspaces
# This script initializes the desktop environment and starts Selkies

set -e

echo "=========================================="
echo "Selkies Desktop Environment Initialization"
echo "=========================================="

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

# Start PulseAudio
echo "Starting PulseAudio..."
pulseaudio --start --log-target=journal
sleep 1
if pulseaudio --check; then
    echo "✓ PulseAudio is running"
else
    echo "WARNING: PulseAudio failed to start, audio will not be available"
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

# Start Selkies web server
cd /opt/selkies-gstreamer
python3 -m selkies_gstreamer.web \
    --port=$SELKIES_PORT \
    --metrics_port=$SELKIES_METRICS_PORT \
    --enable_audio=$SELKIES_ENABLE_AUDIO \
    --enable_resize=$SELKIES_ENABLE_RESIZE &

SELKIES_PID=$!

# Wait for Selkies to be ready
wait_for_service "Selkies Web Interface" $SELKIES_PORT 60

# If running with Coder agent, start it now
if [ -n "$CODER_AGENT_TOKEN" ]; then
    echo "Starting Coder agent..."
    if [ -n "$CODER_AGENT_INIT_SCRIPT" ]; then
        eval "$CODER_AGENT_INIT_SCRIPT"
    fi
fi

echo ""
echo "=========================================="
echo "✓ Selkies Desktop Environment is Ready!"
echo "=========================================="
echo "Access the desktop at: http://localhost:$SELKIES_PORT"
echo "Display: $DISPLAY @ $RESOLUTION"
echo "Video Encoder: $SELKIES_ENCODER"
echo "Video Bitrate: $(($SELKIES_VIDEO_BITRATE / 1000000)) Mbps"
echo "Audio Enabled: $SELKIES_ENABLE_AUDIO"
echo "=========================================="
echo ""

# Keep the container running
echo "Container is running. Press Ctrl+C to stop..."

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down services..."

    # Kill Selkies
    if [ -n "$SELKIES_PID" ]; then
        kill $SELKIES_PID 2>/dev/null || true
    fi

    # Kill XFCE
    if [ -n "$XFCE_PID" ]; then
        kill $XFCE_PID 2>/dev/null || true
    fi

    # Stop PulseAudio
    pulseaudio --kill 2>/dev/null || true

    # Kill X server
    pkill -f "Xvfb $DISPLAY" 2>/dev/null || true

    echo "Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Wait for processes
wait $SELKIES_PID