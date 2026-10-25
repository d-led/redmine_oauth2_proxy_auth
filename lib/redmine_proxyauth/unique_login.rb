require 'securerandom'

module RedmineProxyauth
  # Redmine requires a unique login, but the local part of an e-mail address is
  # only unique within its domain. Two people called john (john@a.example and
  # john@b.example) both read "john" from the proxy headers; without this module
  # the second one could never be provisioned.
  module UniqueLogin
    FALLBACK = 'user'.freeze
    NUMBERED_CANDIDATES = 9

    module_function

    # @param email [String] e-mail asserted by the proxy
    # @param taken [Proc] whether a login is already in use (injected for testing)
    def for(email, taken: nil)
      taken ||= ->(login) { User.exists?(login: login) }

      local_part = local_part_of(email)

      candidate(local_part, email, taken) || "#{local_part}-#{SecureRandom.hex(4)}"
    end

    def candidate(local_part, email, taken)
      candidates(local_part, email).find { |login| !taken.call(login) }
    end

    def candidates(local_part, email)
      [local_part, email.to_s.downcase] +
        (1..NUMBERED_CANDIDATES).map { |suffix| "#{local_part}-#{suffix}" }
    end

    def local_part_of(email)
      local_part = email.to_s.split('@').first.to_s.gsub(/[^a-zA-Z0-9\-_@.]/, '-').downcase

      local_part.empty? ? FALLBACK : local_part
    end
  end
end
