module Api
  module V3
    # account (the account itself, devices, purchases, tokens) is granted only
    # to applications registered with it; third parties can't request it.
    module Scopes
      DEFAULT = "read write"
      FIRST_PARTY = "read write account"

      def self.for(application)
        application.scopes.include?("account") ? FIRST_PARTY : DEFAULT
      end
    end
  end
end
