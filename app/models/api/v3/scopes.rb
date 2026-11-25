module Api
  module V3
    # account (the account itself, devices, purchases, tokens) is granted only
    # to applications registered with it; third parties can't request it.
    module Scopes
      DEFAULT = "read write"
      FIRST_PARTY = "read write account"

      def self.for(application)
        first_party?(application) ? FIRST_PARTY : DEFAULT
      end

      # Whether the application is one of Feedbin's own.
      def self.first_party?(application)
        application.scopes.include?("account")
      end

      # Marks the application with this client id as Feedbin's own: it and its
      # live tokens, the ones created in settings included, get the account
      # scope. Run it from a console, or as `rails "api_v3:first_party[uid]"`.
      # Returns what it did, as a sentence.
      def self.first_party!(uid)
        application = Doorkeeper::Application.find_by!(uid: uid)
        application.update!(scopes: FIRST_PARTY)
        tokens = application.access_tokens.where(revoked_at: nil).update_all(scopes: FIRST_PARTY)
        "#{application.name}: scopes #{application.scopes}; #{tokens} tokens upgraded"
      end
    end
  end
end
