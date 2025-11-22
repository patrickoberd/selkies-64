#!/bin/bash
# Patch Selkies client to use root path WebSocket for Coder compatibility
# This script modifies /opt/gst-web/app.js to change WebSocket path from
# /webrtc/signalling/ to / (root path) which Coder v2.28.3 can proxy correctly

set -e

echo "Patching Selkies WebSocket path for Coder compatibility..."

# Copy app.js to /tmp for patching (avoid permission issues in /opt/gst-web)
sudo cp /opt/gst-web/app.js /tmp/app.js.original
sudo cp /opt/gst-web/app.js /tmp/app.js
echo "✓ Copied app.js to /tmp for patching"

# Patch WebSocket URL construction to use root path instead of /webrtc/signalling/
# Original: protocol + window.location.host + "/" + app.appName + "/signalling/"
# Patched:  protocol + window.location.host + "/"
sed -i 's|protocol + window.location.host + "/" + app.appName + "/signalling/"|protocol + window.location.host + "/"|g' /tmp/app.js

# Verify patch was applied
if grep -q 'protocol + window.location.host + "/"' /tmp/app.js && \
   ! grep -q 'protocol + window.location.host + "/" + app.appName + "/signalling/"' /tmp/app.js; then
    echo "✓ Successfully patched WebSocket path to root /"

    # Copy patched file back to /opt/gst-web
    sudo cp /tmp/app.js /opt/gst-web/app.js
    echo "✓ Deployed patched app.js"
    echo "  WebSocket will now connect to: wss://HOST/"
    echo "  NGINX will rewrite this to: http://localhost:8081/webrtc/signalling/"
else
    echo "⚠ WARNING: Patch may not have been applied correctly"
    echo "  Showing current WebSocket URL construction:"
    grep "new WebRTCDemoSignalling" /tmp/app.js
    exit 1
fi
