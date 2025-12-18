#! /usr/bin/env ruby
# Configure session cookie to use root path (/) so all paths share the same session.
# This prevents redirect loops caused by different paths having different session cookies.
# This runs as a Rails initializer, so Rails.application.config is available

# Set session cookie path to root
# This must be set before any sessions are created
Rails.application.config.session_options[:path] = '/'

# Log that we've set the session path
Rails.logger.info "[Session Config] Session cookie path set to '/' to prevent redirect loops" if defined?(Rails.logger)

