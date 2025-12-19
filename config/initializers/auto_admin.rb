# Auto-promote users to admin based on email list
# This runs after users are created via redmine_proxyauth plugin
#
# IMPORTANT: Rails does NOT automatically load initializers from plugin directories.
# This file must be copied to Redmine's main config/initializers/ directory to be executed.
# If this file is in the plugin directory, it will NOT run.

# Guard: Only run if this file is in the main config/initializers/ directory
# (not in the plugin's config/initializers/ subdirectory)
if __FILE__.include?('plugins/') && __FILE__.include?('config/initializers')
  Rails.logger.warn "[Auto Admin] Initializer is in plugin directory and will not be loaded. Copy to config/initializers/ to enable." if defined?(Rails.logger)
else
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
end

