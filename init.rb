require_relative 'lib/redmine_proxyauth/account_controller_patch'

Redmine::Plugin.register :redmine_oauth2_proxy_auth do
  name 'Redmine OAuth2 Proxy Authentication'
  author 'Dmitry Ledentsov, Alexander Vowinkel (original redmine_proxyauth)'
  description 'Log in users via HTTP headers set by oauth2-proxy. Fork of redmine_proxyauth with enhanced GitHub OAuth2 support and seamless auto-login.'
  version '0.0.1'
  url 'https://github.com/d-led/redmine_oauth2_proxy_auth'
  author_url 'https://github.com/d-led'

  requires_redmine version_or_higher: '5.1.0'

  # No settings page needed - configuration is done via environment variables
  # Original redmine_proxyauth had OIDC settings, but we use oauth2-proxy which handles OAuth2/OIDC
end

# Log plugin loading
Rails.logger.info "[OAuth2 Proxy Auth] Plugin registered: redmine_oauth2_proxy_auth v0.1.0" if defined?(Rails.logger)
