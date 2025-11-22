#!/bin/bash
# Patch Selkies client to use root path WebSocket for Coder compatibility
# This script modifies /opt/gst-web/app.js to change WebSocket path from
# /webrtc/signalling/ to / (root path) which Coder v2.28.3 can proxy correctly

set -e

echo "Patching Selkies WebSocket path for Coder compatibility..."

# Backup original file
if [ ! -f /opt/gst-web/app.js.original ]; then
    cp /opt/gst-web/app.js /opt/gst-web/app.js.original
    echo "✓ Backed up original app.js"
fi

# Patch WebSocket URL construction to use root path instead of /webrtc/signalling/
# Original: protocol + window.location.host + "/" + app.appName + "/signalling/"
# Patched:  protocol + window.location.host + "/"
sed -i 's|protocol + window.location.host + "/" + app.appName + "/signalling/"|protocol + window.location.host + "/"|g' /opt/gst-web/app.js

# Verify patch was applied
if grep -q 'protocol + window.location.host + "/"' /opt/gst-web/app.js && \
   ! grep -q 'protocol + window.location.host + "/" + app.appName + "/signalling/"' /opt/gst-web/app.js; then
    echo "✓ Successfully patched WebSocket path to root /"
    echo "  WebSocket will now connect to: wss://HOST/"
    echo "  NGINX will rewrite this to: http://localhost:8081/webrtc/signalling/"
else
    echo "⚠ WARNING: Patch may not have been applied correctly"
    echo "  Showing current WebSocket URL construction:"
    grep "new WebRTCDemoSignalling" /opt/gst-web/app.js
    exit 1
fi
