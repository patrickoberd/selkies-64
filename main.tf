terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  namespace = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"

  # Parse display resolution
  resolution_parts = split("x", data.coder_parameter.display_resolution.value)
  display_width    = local.resolution_parts[0]
  display_height   = local.resolution_parts[1]

  # Container image
  # TODO: Update this to your own GHCR repo after building
  container_image = "ghcr.io/${data.coder_parameter.image_registry.value}/selkies-coder:${data.coder_parameter.image_tag.value}"
}

# ============================================================================
# PARAMETERS - User-configurable workspace options
# ============================================================================

# Image configuration (mutable)
data "coder_parameter" "image_registry" {
  name         = "image_registry"
  display_name = "Image Registry"
  description  = "GitHub Container Registry username or org"
  type         = "string"
  default      = "selkies-project"
  icon         = "/icon/docker.svg"
  mutable      = true
  order        = 1
}

data "coder_parameter" "image_tag" {
  name         = "image_tag"
  display_name = "Image Tag"
  description  = "Container image version tag"
  type         = "string"
  default      = "latest"
  icon         = "/icon/git.svg"
  mutable      = true
  order        = 2

  option {
    name  = "Latest"
    value = "latest"
  }
  option {
    name  = "Stable"
    value = "stable"
  }
  option {
    name  = "v1.0.0"
    value = "v1.0.0"
  }
}

# Resource parameters (immutable - set at creation)
data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores (guaranteed: 2, limit configurable)"
  type         = "string"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = false
  order        = 10

  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of RAM allocated to workspace"
  type         = "string"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = false
  order        = 11

  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent storage for home directory"
  type         = "number"
  default      = 50
  icon         = "/icon/database.svg"
  mutable      = false
  order        = 12

  validation {
    min = 10
    max = 500
  }
}

# Display parameters (mutable)
data "coder_parameter" "display_resolution" {
  name         = "display_resolution"
  display_name = "Display Resolution"
  description  = "Desktop screen resolution"
  type         = "string"
  default      = "1920x1080"
  icon         = "/icon/display.svg"
  mutable      = true
  order        = 20

  option {
    name  = "1280x720 (HD)"
    value = "1280x720"
  }
  option {
    name  = "1600x900 (HD+)"
    value = "1600x900"
  }
  option {
    name  = "1920x1080 (Full HD)"
    value = "1920x1080"
  }
  option {
    name  = "2560x1440 (QHD)"
    value = "2560x1440"
  }
  option {
    name  = "3840x2160 (4K)"
    value = "3840x2160"
  }
}

data "coder_parameter" "display_refresh" {
  name         = "display_refresh"
  display_name = "Refresh Rate (Hz)"
  description  = "Display refresh rate"
  type         = "string"
  default      = "30"
  icon         = "/icon/display.svg"
  mutable      = true
  order        = 21

  option {
    name  = "24 Hz"
    value = "24"
  }
  option {
    name  = "30 Hz (Balanced)"
    value = "30"
  }
  option {
    name  = "60 Hz (Smooth)"
    value = "60"
  }
}

# Video encoding parameters (mutable)
data "coder_parameter" "video_encoder" {
  name         = "video_encoder"
  display_name = "Video Encoder"
  description  = "Video encoding method (CPU-based)"
  type         = "string"
  default      = "x264enc"
  icon         = "/icon/video.svg"
  mutable      = true
  order        = 30

  option {
    name  = "H.264 (x264enc)"
    value = "x264enc"
  }
  option {
    name  = "VP8 (Good compatibility)"
    value = "vp8enc"
  }
  option {
    name  = "VP9 (Better quality)"
    value = "vp9enc"
  }
}

data "coder_parameter" "video_bitrate" {
  name         = "video_bitrate"
  display_name = "Video Bitrate"
  description  = "Video streaming quality"
  type         = "string"
  default      = "4000000"
  icon         = "/icon/video.svg"
  mutable      = true
  order        = 31

  option {
    name  = "2 Mbps (Low)"
    value = "2000000"
  }
  option {
    name  = "4 Mbps (Medium)"
    value = "4000000"
  }
  option {
    name  = "8 Mbps (High)"
    value = "8000000"
  }
}

# Audio parameters (mutable)
data "coder_parameter" "enable_audio" {
  name         = "enable_audio"
  display_name = "Enable Audio"
  description  = "Enable audio streaming"
  type         = "string"
  default      = "true"
  icon         = "/icon/audio.svg"
  mutable      = true
  order        = 40

  option {
    name  = "Enabled"
    value = "true"
  }
  option {
    name  = "Disabled"
    value = "false"
  }
}

data "coder_parameter" "audio_bitrate" {
  name         = "audio_bitrate"
  display_name = "Audio Bitrate"
  description  = "Audio streaming quality"
  type         = "string"
  default      = "128000"
  icon         = "/icon/audio.svg"
  mutable      = true
  order        = 41

  option {
    name  = "64 kbps"
    value = "64000"
  }
  option {
    name  = "128 kbps"
    value = "128000"
  }
  option {
    name  = "256 kbps"
    value = "256000"
  }
}

# System parameters (mutable)
data "coder_parameter" "timezone" {
  name         = "timezone"
  display_name = "Timezone"
  description  = "System timezone"
  type         = "string"
  default      = "UTC"
  icon         = "/emojis/1f551.png"
  mutable      = true
  order        = 50

  option {
    name  = "UTC"
    value = "UTC"
  }
  option {
    name  = "US Eastern"
    value = "America/New_York"
  }
  option {
    name  = "US Pacific"
    value = "America/Los_Angeles"
  }
  option {
    name  = "Europe/London"
    value = "Europe/London"
  }
  option {
    name  = "Europe/Berlin"
    value = "Europe/Berlin"
  }
  option {
    name  = "Asia/Tokyo"
    value = "Asia/Tokyo"
  }
}

# ============================================================================
# CODER AGENT
# ============================================================================

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "Waiting for Selkies to be ready..."
    timeout 120 bash -c 'until nc -z localhost 8080; do sleep 1; done'

    if [ $? -eq 0 ]; then
      echo "✓ Selkies is ready at http://localhost:8080"
    else
      echo "⚠ Selkies startup timeout - check logs"
    fi

    echo "✓ Workspace is ready!"
  EOT

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    web_terminal           = true
    port_forwarding_helper = true
    ssh_helper             = true
  }

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
}

# ============================================================================
# CODER APPS
# ============================================================================

resource "coder_app" "selkies" {
  agent_id     = coder_agent.main.id
  slug         = "desktop"
  display_name = "Desktop (Selkies)"
  url          = "http://localhost:8080"
  icon         = "/icon/desktop.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080"
    interval  = 5
    threshold = 10
  }
}

resource "coder_app" "metrics" {
  agent_id     = coder_agent.main.id
  slug         = "metrics"
  display_name = "Metrics"
  url          = "http://localhost:9090/metrics"
  icon         = "/icon/analytics.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:9090/metrics"
    interval  = 30
    threshold = 5
  }
}

# ============================================================================
# KUBERNETES RESOURCES
# ============================================================================

resource "kubernetes_namespace" "workspace" {
  metadata {
    name = local.namespace
    labels = {
      "coder.owner"     = data.coder_workspace_owner.me.name
      "coder.workspace" = data.coder_workspace.me.name
      "app.kubernetes.io/managed-by" = "coder"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "home-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = kubernetes_namespace.workspace.metadata[0].name

    labels = {
      "coder.owner"     = data.coder_workspace_owner.me.name
      "coder.workspace" = data.coder_workspace.me.name
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "exoscale-sbs"

    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = kubernetes_namespace.workspace.metadata[0].name

    labels = {
      "app.kubernetes.io/name"     = "selkies-workspace"
      "app.kubernetes.io/instance" = data.coder_workspace.me.name
      "app.kubernetes.io/owner"    = data.coder_workspace_owner.me.name
      "coder.owner"                = data.coder_workspace_owner.me.name
      "coder.workspace"            = data.coder_workspace.me.name
    }
  }

  spec {
    # Security context - run as non-root
    security_context {
      run_as_user  = 1000
      run_as_group = 1000
      fs_group     = 1000
    }

    # Node selection - run on coder nodes
    node_selector = {
      "workload-type" = "coder"
    }

    # Main container
    container {
      name  = "selkies"
      image = local.container_image

      # Always pull to get latest updates
      image_pull_policy = "Always"

      # Command - combine Selkies startup with Coder agent
      command = ["/bin/bash", "-c"]
      args = [<<-EOT
        # Start Selkies entrypoint in background
        /opt/scripts/entrypoint.sh &

        # Store the entrypoint PID
        ENTRYPOINT_PID=$!

        # Give Selkies time to initialize
        sleep 10

        # Run Coder agent init script
        ${coder_agent.main.init_script}

        # Wait for entrypoint to finish (it won't, keeps container running)
        wait $ENTRYPOINT_PID
      EOT
      ]

      # Environment variables - Coder agent
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      env {
        name  = "CODER_AGENT_INIT_SCRIPT"
        value = coder_agent.main.init_script
      }

      # Environment variables - System
      env {
        name  = "USER"
        value = "coder"
      }

      env {
        name  = "HOME"
        value = "/home/coder"
      }

      env {
        name  = "TZ"
        value = data.coder_parameter.timezone.value
      }

      # Environment variables - Display
      env {
        name  = "DISPLAY"
        value = ":0"
      }

      env {
        name  = "RESOLUTION"
        value = data.coder_parameter.display_resolution.value
      }

      env {
        name  = "SELKIES_DISPLAY_SIZEW"
        value = local.display_width
      }

      env {
        name  = "SELKIES_DISPLAY_SIZEH"
        value = local.display_height
      }

      env {
        name  = "SELKIES_DISPLAY_REFRESH"
        value = data.coder_parameter.display_refresh.value
      }

      # Environment variables - Selkies configuration
      env {
        name  = "SELKIES_ENCODER"
        value = data.coder_parameter.video_encoder.value
      }

      env {
        name  = "SELKIES_VIDEO_BITRATE"
        value = data.coder_parameter.video_bitrate.value
      }

      env {
        name  = "SELKIES_FRAMERATE"
        value = data.coder_parameter.display_refresh.value
      }

      env {
        name  = "SELKIES_ENABLE_AUDIO"
        value = data.coder_parameter.enable_audio.value
      }

      env {
        name  = "SELKIES_AUDIO_BITRATE"
        value = data.coder_parameter.audio_bitrate.value
      }

      env {
        name  = "SELKIES_ENABLE_RESIZE"
        value = "true"
      }

      env {
        name  = "SELKIES_PORT"
        value = "8080"
      }

      env {
        name  = "SELKIES_METRICS_PORT"
        value = "9090"
      }

      # Resources
      resources {
        requests = {
          cpu    = "2"
          memory = "${data.coder_parameter.memory.value}Gi"
        }
        limits = {
          cpu    = data.coder_parameter.cpu.value
          memory = "${data.coder_parameter.memory.value}Gi"
        }
      }

      # Volume mounts
      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }

      volume_mount {
        mount_path = "/dev/shm"
        name       = "dshm"
      }

      volume_mount {
        mount_path = "/tmp"
        name       = "tmp"
      }

      # Startup probe - give plenty of time for image pull and init
      startup_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 30
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 180  # 30 minutes total
      }

      # Liveness probe
      liveness_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 60
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3
      }

      # Readiness probe
      readiness_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 45
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 3
      }
    }

    # Volumes
    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
      }
    }

    volume {
      name = "dshm"
      empty_dir {
        medium = "Memory"
        size_limit = "2Gi"
      }
    }

    volume {
      name = "tmp"
      empty_dir {
        size_limit = "5Gi"
      }
    }
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "workspace_info" {
  value = <<-EOT
    Selkies Desktop Workspace
    ========================

    Access Points:
    - Desktop: Click "Desktop (Selkies)" in Coder dashboard
    - Metrics: Click "Metrics" to view performance data
    - Terminal: Use web terminal or SSH

    Configuration:
    - Resolution: ${data.coder_parameter.display_resolution.value} @ ${data.coder_parameter.display_refresh.value}Hz
    - Video Encoder: ${data.coder_parameter.video_encoder.value}
    - Video Bitrate: ${tonumber(data.coder_parameter.video_bitrate.value) / 1000000} Mbps
    - Audio: ${data.coder_parameter.enable_audio.value == "true" ? "Enabled" : "Disabled"}

    Resources:
    - CPU: ${data.coder_parameter.cpu.value} cores
    - Memory: ${data.coder_parameter.memory.value} GB
    - Storage: ${data.coder_parameter.disk_size.value} GB

    Tips:
    - Lower resolution/bitrate for slow connections
    - Disable audio if not needed to save bandwidth
    - Use VP8/VP9 encoders for better compression
  EOT
}