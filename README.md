# Redmine OAuth2 Proxy Authentication

Log in users via HTTP headers set by oauth2-proxy.

This is a fork of [redmine_proxyauth](https://github.com/FES-Ehemalige/redmine_proxyauth) with enhanced support for:
- GitHub OAuth2 (via API token lookup)
- Seamless auto-login from OAuth2 proxy headers
- Session cookie path configuration to prevent redirect loops
- Auto-admin promotion based on email list
- Trusted proxy header configuration

## Original Plugin

This plugin is based on the work by Alexander Vowinkel and FES-Ehemalige e.V.
Original repository: https://github.com/FES-Ehemalige/redmine_proxyauth

## Usage

This plugin can be used if you are securing Redmine with an instance of [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/).

The plugin supports:
- JWT tokens (OIDC providers like Google, Azure)
- GitHub OAuth2 access tokens (via API lookup)
- Header-based fallback (X-Auth-Request-Email, X-Forwarded-Email)

Users are automatically created and logged in when they first access Redmine through oauth2-proxy.
If the required headers are missing, users will be redirected to an error page.

## Configuration

Configuration is done via environment variables:
- `REDMINE_ADMIN_EMAILS`: Comma-separated list of emails to auto-promote to admin
- `TRUSTED_PROXY_IPS`: Comma-separated list of IP addresses or CIDR ranges to trust as proxies (e.g., `"10.0.0.0/8,172.16.0.0/12"`). If not set, defaults to common private network ranges suitable for Docker/local development.
- `DEBUG_PROXY_HEADERS`: Set to "true" to enable debug logging of proxy headers

## Installation

### Important: Copy Initializers

**Rails does NOT automatically load initializers from plugin directories.** The plugin includes several initializers in `config/initializers/` that must be copied to Redmine's main `config/initializers/` directory to work.

The plugin includes initializers for:
- Auto-login from OAuth2 headers (prevents redirect loops)
- Session cookie path configuration (prevents redirect loops from different cookie paths)
- Trusted proxy configuration
- Auto-admin promotion
- Debug header logging

### Docker Installation

When using Docker, copy the initializers during the build process. The plugin includes initializers in `config/initializers/` that must be copied to Redmine's main `config/initializers/` directory:

```dockerfile
# Clone the plugin
RUN git clone https://github.com/d-led/redmine_oauth2_proxy_auth.git /usr/src/redmine/plugins/redmine_proxyauth

# Copy initializers from plugin to Redmine's config/initializers/
# Rails does NOT auto-load initializers from plugin directories - they must be in config/initializers/
RUN if [ -d /usr/src/redmine/plugins/redmine_proxyauth/config/initializers ]; then \
      mkdir -p /usr/src/redmine/config/initializers && \
      cp -v /usr/src/redmine/plugins/redmine_proxyauth/config/initializers/*.rb /usr/src/redmine/config/initializers/ && \
      echo "✅ Copied $(ls /usr/src/redmine/plugins/redmine_proxyauth/config/initializers/*.rb | wc -l) initializers from plugin to Redmine config/initializers/"; \
    else \
      echo "⚠️  Warning: Plugin initializers directory not found"; \
    fi
```

**Important:** The plugin directory name in Redmine is `redmine_proxyauth` (even though the GitHub repository is `redmine_oauth2_proxy_auth`). Make sure your paths match this.

See `Dockerfile.example` for a complete example.

### Manual Installation

If installing manually (not using Docker), copy the initializers after installing the plugin:

```bash
# After installing the plugin to plugins/redmine_proxyauth/
# Make sure the plugin directory is named 'redmine_proxyauth'
cp plugins/redmine_proxyauth/config/initializers/*.rb config/initializers/
```

The initializers will then be loaded automatically by Rails on the next application start.

**Note:** The plugin directory must be named `redmine_proxyauth` in your Redmine installation (this matches the plugin's internal name, even though the GitHub repository is `redmine_oauth2_proxy_auth`).
