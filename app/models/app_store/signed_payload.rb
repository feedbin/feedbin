# A JWS from Apple: a notification, a transaction or renewal info. Decoded only
# once its certificate chain ends at Apple's root (JwsVerifier).
module AppStore
  class SignedPayload
    class Invalid < StandardError; end

    # Xcode's StoreKit testing signs with a local certificate, so a development
    # server takes a payload as it is. Nothing else does.
    def self.decode(token, verify: !Rails.env.development?)
      raise Invalid, "The payload is not signed by Apple." if verify && !JwsVerifier.valid?(token)
      read(token)
    end

    # The claims of a payload already known to be Apple's: one nested in a
    # verified notification, or one from Apple's own API over TLS.
    def self.read(token)
      _, claims, _ = token.to_s.split(".")
      JSON.parse(Base64.urlsafe_decode64(claims.to_s))
    rescue JSON::ParserError, ArgumentError
      raise Invalid, "The payload could not be read."
    end
  end
end
