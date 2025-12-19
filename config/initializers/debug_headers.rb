# Debug: Log incoming headers to help troubleshoot proxy header issues
#
# IMPORTANT: Rails does NOT automatically load initializers from plugin directories.
# This file must be copied to Redmine's main config/initializers/ directory to be executed.
# If this file is in the plugin directory, it will NOT run.

# Guard: Only run if this file is in the main config/initializers/ directory
# (not in the plugin's config/initializers/ subdirectory)
if __FILE__.include?('plugins/') && __FILE__.include?('config/initializers')
  Rails.logger.warn "[Debug Headers] Initializer is in plugin directory and will not be loaded. Copy to config/initializers/ to enable." if defined?(Rails.logger)
else
  Rails.application.config.to_prepare do
  # Always log in production to help debug proxy issues
  if Rails.env.production?
    ActionController::Base.class_eval do
      before_action :log_proxy_headers, if: -> { Rails.logger }
      
      private
      
      def log_proxy_headers
        # Log relevant proxy headers (excluding sensitive tokens)
        headers_to_check = [
          'HTTP_X_AUTH_REQUEST_USER',
          'HTTP_X_AUTH_REQUEST_EMAIL',
          'HTTP_X_FORWARDED_USER',
          'HTTP_X_FORWARDED_EMAIL'
        ]
        
        # Check for token headers without logging their values
        token_headers_present = [
          'HTTP_X_AUTH_REQUEST_ACCESS_TOKEN',
          'HTTP_X_AUTH_REQUEST_ID_TOKEN',
          'HTTP_X_FORWARDED_ACCESS_TOKEN',
          'HTTP_AUTHENTICATION_TOKEN'
        ].any? { |h| request.headers[h].present? }
        
        found_headers = headers_to_check.select { |h| request.headers[h].present? }
        if found_headers.any?
          token_info = token_headers_present ? " (token headers present)" : " (no token headers)"
          Rails.logger.info "[Proxy Headers] Found headers: #{found_headers.map { |h| "#{h}=#{request.headers[h]}" }.join(', ')}#{token_info}"
        else
          token_info = token_headers_present ? " (token headers present but no user headers)" : ""
          Rails.logger.warn "[Proxy Headers] No proxy headers found#{token_info}. Available headers: #{request.headers.env.keys.grep(/HTTP_/).join(', ')}"
        end
      end
    end
  end
  end
end

