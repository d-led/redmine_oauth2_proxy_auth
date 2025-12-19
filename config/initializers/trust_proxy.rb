# Trust proxy headers from oauth2-proxy
# This allows Redmine to read X-Forwarded-* and X-Auth-Request-* headers
#
# IMPORTANT: Rails does NOT automatically load initializers from plugin directories.
# This file must be copied to Redmine's main config/initializers/ directory to be executed.
# If this file is in the plugin directory, it will NOT run.

# Guard: Only run if this file is in the main config/initializers/ directory
# (not in the plugin's config/initializers/ subdirectory)
if __FILE__.include?('plugins/') && __FILE__.include?('config/initializers')
  Rails.logger.warn "[Trust Proxy] Initializer is in plugin directory and will not be loaded. Copy to config/initializers/ to enable." if defined?(Rails.logger)
else
  Rails.application.config.force_ssl = false

  # Trust all proxies in Docker network (oauth2-proxy is on the same network)
  # In production, you should specify the exact proxy IPs
  # Docker networks use private IP ranges, so we trust all private IPs
  Rails.application.config.action_dispatch.trusted_proxies = [
    IPAddr.new("10.0.0.0/8"),     # Private network
    IPAddr.new("172.16.0.0/12"),   # Docker network
    IPAddr.new("192.168.0.0/16"),  # Private network
    IPAddr.new("127.0.0.1"),       # Localhost
    IPAddr.new("::1")              # IPv6 localhost
  ]

  # Enable reading of X-Forwarded-* headers
  Rails.application.config.action_dispatch.x_forwarded_host = true
  Rails.application.config.action_dispatch.x_forwarded_for = true
end

