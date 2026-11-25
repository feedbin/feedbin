# A JWS from Apple: a notification, a transaction or renewal info. Decoded only
# once its certificate chain ends at Apple's root (JwsVerifier).
module AppStore
  class SignedPayload
    class Invalid < StandardError; end

    # Apple's signature is checked, with one exception: Xcode's StoreKit testing
    # signs with a certificate of its own, so a development server takes what
    # says it is from Xcode as it is. Apple's sandbox and production are
    # checked there too.
    def self.decode(token)
      claims = read(token)
      return claims if Rails.env.development? && claims["environment"] == "Xcode"
      raise Invalid, "The payload is not signed by Apple." unless JwsVerifier.valid?(token)
      claims
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
