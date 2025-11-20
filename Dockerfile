# Multi-stage Dockerfile for Selkies-gstreamer on Coder
# Base: Ubuntu 22.04 LTS
# Purpose: WebRTC desktop streaming for Coder workspaces
# Version: 1.0.0

# ============================================================================
# Stage 1: Base System Setup
# ============================================================================
FROM ubuntu:22.04 AS base

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install base system packages and dependencies
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    sudo \
    locales \
    tzdata \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    # Build tools (needed for some pip packages)
    build-essential \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    # Network tools
    net-tools \
    iputils-ping \
    netcat-openbsd \
    # Process management
    supervisor \
    dbus \
    dbus-x11 \
    # Audio support
    pulseaudio \
    pavucontrol \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8

# ============================================================================
# Stage 2: X11 and Desktop Environment
# ============================================================================
FROM base AS desktop

# Install X11 and display server components
RUN apt-get update && apt-get install -y \
    # X11 server and utilities
    xvfb \
    xorg \
    x11-xserver-utils \
    x11-utils \
    x11-apps \
    xinit \
    # Software rendering (CPU-based)
    xserver-xorg-video-dummy \
    mesa-utils \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    # Input devices
    xserver-xorg-input-all \
    xinput \
    # Fonts
    fonts-dejavu-core \
    fonts-liberation \
    fonts-ubuntu \
    fonts-noto \
    fonts-noto-color-emoji \
    # XFCE desktop environment (lightweight)
    xfce4 \
    xfce4-terminal \
    xfce4-whiskermenu-plugin \
    xfce4-taskmanager \
    thunar \
    thunar-volman \
    # Window manager
    xfwm4 \
    xfwm4-themes \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Stage 3: GStreamer and Media Libraries
# ============================================================================
FROM desktop AS gstreamer

# Install GStreamer and related packages
RUN apt-get update && apt-get install -y \
    # GStreamer core
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-vaapi \
    gstreamer1.0-libav \
    gstreamer1.0-gl \
    gstreamer1.0-gtk3 \
    gstreamer1.0-pulseaudio \
    gstreamer1.0-alsa \
    gstreamer1.0-x \
    # Development libraries
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    # Python GStreamer bindings
    python3-gst-1.0 \
    gir1.2-gstreamer-1.0 \
    gir1.2-gst-plugins-base-1.0 \
    # Video codecs and tools
    libx264-dev \
    libvpx-dev \
    libopus-dev \
    libwebp-dev \
    # WebRTC dependencies
    libnice-dev \
    libsrtp2-dev \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Stage 4: Selkies-gstreamer Installation
# ============================================================================
FROM gstreamer AS selkies

# Install Python dependencies for Selkies
RUN pip3 install --no-cache-dir \
    # Web framework
    aiohttp \
    aiortc \
    # WebRTC signaling
    websockets \
    msgpack \
    # Monitoring and logging
    prometheus_client \
    structlog \
    # Utilities
    pyyaml \
    Jinja2 \
    watchdog

# Clone and install Selkies-gstreamer
# Using a specific version for reproducibility
ARG SELKIES_VERSION=v1.6.0
WORKDIR /opt
RUN git clone --depth 1 --branch ${SELKIES_VERSION} \
    https://github.com/selkies-project/selkies-gstreamer.git \
    && cd selkies-gstreamer \
    && pip3 install -e .

# Copy Selkies web assets
RUN cp -r /opt/selkies-gstreamer/addons/web /opt/selkies-web

# ============================================================================
# Stage 5: Development Tools
# ============================================================================
FROM selkies AS development

# Install common development tools
RUN apt-get update && apt-get install -y \
    # Editors
    vim \
    nano \
    # Version control
    git \
    git-lfs \
    # Development languages and tools
    nodejs \
    npm \
    golang-go \
    rustc \
    cargo \
    # Container tools
    docker.io \
    kubectl \
    # Browsers
    firefox \
    chromium-browser \
    # File manager
    pcmanfm \
    # Archive tools
    zip \
    unzip \
    tar \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Stage 6: User Configuration
# ============================================================================
FROM development AS final

# Create non-root user
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=coder

RUN groupadd -g ${GROUP_ID} ${USERNAME} \
    && useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd \
    && chmod 0440 /etc/sudoers.d/nopasswd

# Create necessary directories
RUN mkdir -p /var/run/user/${USER_ID} \
    && chown -R ${USERNAME}:${USERNAME} /var/run/user/${USER_ID} \
    && chmod 700 /var/run/user/${USER_ID}

# Copy configuration files
COPY --chown=${USERNAME}:${USERNAME} build/desktop-configs/xfce4/ /home/${USERNAME}/.config/xfce4/
COPY --chown=${USERNAME}:${USERNAME} scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# Set up supervisord configuration
COPY build/supervisor/ /etc/supervisor/conf.d/

# Create required directories
RUN mkdir -p /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix \
    && mkdir -p /var/log/supervisor \
    && chown -R ${USERNAME}:${USERNAME} /var/log/supervisor

# Environment variables for Selkies
ENV DISPLAY=:0 \
    XDG_RUNTIME_DIR=/var/run/user/${USER_ID} \
    PULSE_SERVER=unix:/tmp/pulse/native \
    SELKIES_ENCODER=x264enc \
    SELKIES_ENABLE_RESIZE=true \
    SELKIES_ENABLE_AUDIO=true \
    SELKIES_ENABLE_BASIC_AUTH=false \
    SELKIES_PORT=8080 \
    SELKIES_METRICS_PORT=9090

# Switch to non-root user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Expose ports
# 8080: Selkies web interface
# 9090: Prometheus metrics
EXPOSE 8080 9090

# Entry point
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]