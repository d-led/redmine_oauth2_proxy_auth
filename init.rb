require_relative 'lib/redmine_proxyauth/account_controller_patch'

Redmine::Plugin.register :redmine_oauth2_proxy_auth do
  name 'Redmine OAuth2 Proxy Authentication'
  author 'Dmitry Ledentsov'
  description 'Log in users via HTTP headers set by oauth2-proxy. Fork of redmine_proxyauth with enhanced GitHub OAuth2 support and seamless auto-login.'
  version '0.1.0'
  url 'https://github.com/d-led/redmine_oauth2_proxy_auth'
  author_url 'https://github.com/d-led'

  requires_redmine version_or_higher: '5.1.0'

  # No settings page needed - configuration is done via environment variables
  # Original redmine_proxyauth had OIDC settings, but we use oauth2-proxy which handles OAuth2/OIDC
end

# Log plugin loading
Rails.logger.info "[OAuth2 Proxy Auth] Plugin registered: redmine_oauth2_proxy_auth v0.1.0" if defined?(Rails.logger)

# Configure session cookie path to root (/) so all paths share the same session
# This prevents redirect loops caused by different paths having different session cookies
# This must be set directly (not in to_prepare) to ensure it runs before any sessions are created
if defined?(Rails) && Rails.application && Rails.application.config
  Rails.application.config.session_options[:path] = '/'
  Rails.logger.info "[OAuth2 Proxy Auth] Session cookie path set to '/' to prevent redirect loops" if defined?(Rails.logger)
end

# Configure trusted proxy headers (for Docker/oauth2-proxy setup)
# This allows Redmine to read X-Forwarded-* and X-Auth-Request-* headers
Rails.application.config.force_ssl = false

# Configure trusted proxies
# Can be set via TRUSTED_PROXY_IPS environment variable (comma-separated list of IPs/CIDR ranges)
# If not set, defaults to common private network ranges (suitable for Docker/local development)
trusted_proxy_ips = ENV['TRUSTED_PROXY_IPS'].to_s.split(',').map(&:strip).reject(&:empty?)
if trusted_proxy_ips.any?
  Rails.application.config.action_dispatch.trusted_proxies = trusted_proxy_ips.map do |ip|
    IPAddr.new(ip)
  end
  Rails.logger.info "[OAuth2 Proxy Auth] Using configured trusted proxies: #{trusted_proxy_ips.join(', ')}"
else
  # Default: Trust common private network ranges (suitable for Docker/local development)
  Rails.application.config.action_dispatch.trusted_proxies = [
    IPAddr.new("10.0.0.0/8"),     # Private network
    IPAddr.new("172.16.0.0/12"),   # Docker network
    IPAddr.new("192.168.0.0/16"),  # Private network
    IPAddr.new("127.0.0.1"),       # Localhost
    IPAddr.new("::1")              # IPv6 localhost
  ]
  Rails.logger.info "[OAuth2 Proxy Auth] Using default trusted proxies (private networks). Set TRUSTED_PROXY_IPS to customize."
end

# Enable reading of X-Forwarded-* headers
Rails.application.config.action_dispatch.x_forwarded_host = true
Rails.application.config.action_dispatch.x_forwarded_for = true

# Auto-login from OAuth2 proxy headers
# This runs before other filters to ensure User.current is set before session_expiration checks
# Use to_prepare (standard Rails plugin pattern) to ensure ApplicationController is loaded
Rails.logger.info "[OAuth2 Proxy Auth] Setting up auto-login from OAuth2 headers" if defined?(Rails.logger)

Rails.application.config.to_prepare do
  Rails.logger.info "[OAuth2 Proxy Auth] to_prepare block executing for auto-login" if defined?(Rails.logger)
  
  unless defined?(ApplicationController) && defined?(User)
    Rails.logger.warn "[OAuth2 Proxy Auth] ApplicationController or User not defined yet, skipping auto-login setup" if defined?(Rails.logger)
    next
  end

  # Check if already patched to avoid duplicate registrations
  already_patched = ApplicationController.private_instance_methods(false).include?(:auto_login_from_oauth2)
  
  unless already_patched
    Rails.logger.info "[OAuth2 Proxy Auth] Registering auto_login_from_oauth2 before_action" if defined?(Rails.logger)
    ApplicationController.class_eval do
      before_action :auto_login_from_oauth2, prepend: true

    private

    def auto_login_from_oauth2
      # Log that the before_action is running (at least on first few requests for debugging)
      Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: Running on #{request.fullpath}" if defined?(Rails.logger)
      
      # Take the email from the trusted proxy headers first
      email = request.headers['X-Auth-Request-Email'] ||
              request.headers['X-Forwarded-Email']
      user_name = request.headers['X-Auth-Request-User'] ||
                  request.headers['X-Forwarded-User']

      # If no OAuth2 headers, check if user is already logged in (normal session)
      if email.blank?
        if User.current&.logged?
          Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: User already logged in (#{User.current.login}), no OAuth2 headers"
        else
          Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: No email header found on #{request.fullpath}"
        end
        return
      end

      Rails.logger.info "[Proxyauth] auto_login_from_oauth2: Found email header: #{email} on #{request.fullpath}"

      # Find user from OAuth2 email
      user = User.find_by_mail(email)
      
      # If OAuth2 headers are present, we MUST sync with them (source of truth)
      # This prevents redirect loops from stale sessions
      if user&.active?
        # If there's a logged-in user but it's NOT the OAuth2 user, clear the stale session
        if User.current&.logged? && User.current.id != user.id
          Rails.logger.warn "[Proxyauth] auto_login_from_oauth2: Stale session detected! Current user: #{User.current.login} (#{User.current.mail}), OAuth2 user: #{user.login} (#{email}). Clearing stale session."
          # Clear the stale session
          reset_session
          User.current = nil
        end
        
        # If user is already logged in and matches OAuth2, we're good
        if User.current&.logged? && User.current.id == user.id
          Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: User already logged in and matches OAuth2 (#{User.current.login})"
          return
        end
      end
      
      # If user doesn't exist, let redmine_proxyauth handle creation on /login
      # But if user exists, auto-login them even on /login route
      if user.nil?
        Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: User with email #{email} not found"
        # Only skip if we're on /login (let proxyauth create the user)
        # On other routes, we can't auto-login a non-existent user
        if request.path == '/login' || request.path.start_with?('/login?')
          Rails.logger.debug "[Proxyauth] auto_login_from_oauth2: Letting redmine_proxyauth handle user creation on /login"
          return
        else
          Rails.logger.warn "[Proxyauth] auto_login_from_oauth2: User not found and not on /login, cannot auto-login"
          return
        end
      end
      
      # User exists - auto-login them even on /login route
      # This provides seamless experience: if user already exists, they're logged in immediately

      # Do not auto-login inactive users
      unless user&.active?
        Rails.logger.warn "[Proxyauth] auto_login_from_oauth2: User #{email} is not active"
        return
      end

      # Optionally keep name in sync with headers (non-empty values only).
      if user_name.present?
        first, last = user_name.split(' ', 2)
        changed = false
        if first.present? && user.firstname != first
          user.firstname = first
          changed = true
        end
        if last.present? && last != '' && user.lastname != last
          user.lastname = last
          changed = true
        end
        user.save(validate: false) if changed
      end

      # Align Redmine's current user and session with the proxy identity.
      # CRITICAL: Set User.current BEFORE setting session, as Redmine's session methods may check it
      User.current = user
      
      # Use Redmine's proper session method if available
      # This method sets both User.current and the session correctly
      if respond_to?(:start_user_session, true)
        send(:start_user_session, user)
        Rails.logger.info "[Proxyauth] auto_login_from_oauth2: Used start_user_session for #{user.login}"
      else
        # Fallback: set the standard session keys manually.
        session[:user_id] = user.id
        # Ensure User.current is set (don't reload from session as it might not be persisted yet)
        User.current = user
        Rails.logger.info "[Proxyauth] auto_login_from_oauth2: Set session manually for #{user.login}"
      end
      
      # CRITICAL: Ensure session is persisted by marking it as changed
      # Rails will automatically write the session cookie if the session is modified
      session[:updated_at] = Time.now.to_i if session.respond_to?(:[]=)
      
      # Force session to be written by accessing it (this marks it as dirty)
      session.load! if session.respond_to?(:load!) && !session.loaded?

      # Verify the login worked
      # Don't reload User.current from session here - we just set it above
      if User.current&.logged?
        Rails.logger.info "[Proxyauth] auto_login_from_oauth2: ✅ Successfully auto-logged in #{user.login} on #{request.fullpath}"
      else
        Rails.logger.warn "[Proxyauth] auto_login_from_oauth2: ⚠️ User.current.logged? is false after setting session. User.current: #{User.current&.id}, session[:user_id]: #{session[:user_id]}"
      end
    rescue => e
      Rails.logger.error "[Proxyauth] auto_login_from_oauth2 error: #{e.class}: #{e.message}"
      Rails.logger.error "[Proxyauth] Backtrace: #{e.backtrace.first(10).join(', ')}" if e.backtrace
    end
    Rails.logger.info "[OAuth2 Proxy Auth] Auto-login before_action registered on ApplicationController" if defined?(Rails.logger)
  else
    Rails.logger.info "[OAuth2 Proxy Auth] Auto-login before_action already registered, skipping" if defined?(Rails.logger)
  end
end

# Auto-promote users to admin based on email list
Rails.application.config.to_prepare do
  if defined?(User)
    # Log configured admin emails on startup
    admin_emails = ENV['REDMINE_ADMIN_EMAILS'].to_s.split(',').map(&:strip).reject(&:empty?)
    if admin_emails.any?
      Rails.logger.info "[Auto Admin] Configured admin emails: #{admin_emails.join(', ')}"
    else
      Rails.logger.info "[Auto Admin] No admin emails configured (REDMINE_ADMIN_EMAILS not set or empty)"
    end
    
    # Hook into user creation/update to auto-promote admins
    User.class_eval do
      # Trigger on both new user creation and email changes
      after_create :auto_promote_to_admin_on_create
      after_save :auto_promote_to_admin_on_email_change, if: -> { respond_to?(:saved_change_to_mail?) && saved_change_to_mail? }
      
      private
      
      def auto_promote_to_admin_on_create
        auto_promote_to_admin
      end
      
      def auto_promote_to_admin_on_email_change
        auto_promote_to_admin
      end
      
      def auto_promote_to_admin
        # Skip if this is not a real User instance (e.g., AnonymousUser)
        return unless respond_to?(:mail) && respond_to?(:admin?)
        return unless persisted?
        
        admin_emails = ENV['REDMINE_ADMIN_EMAILS'].to_s.split(',').map(&:strip).reject(&:empty?)
        return if admin_emails.empty?
        return if admin? # Already admin, skip
        
        if mail.present? && admin_emails.include?(mail)
          # Use update_columns to avoid triggering callbacks again
          update_columns(admin: true, status: User::STATUS_ACTIVE)
          Rails.logger.info "[Auto Admin] Promoted user #{mail} to admin"
        end
      end
    end
  end
end
