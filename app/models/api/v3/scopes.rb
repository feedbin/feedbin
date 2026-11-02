module Api
  module V3
    # Every token gets read and write. Feedbin's own apps also get account:
    # push devices, purchases, deleting the account, and other apps' tokens.
    # An application is Feedbin's when its registered scopes include account;
    # third parties cannot ask for it, or for anything else.
    module Scopes
      DEFAULT = "read write"
      FIRST_PARTY = "read write account"

      def self.for(application)
        application.scopes.include?("account") ? FIRST_PARTY : DEFAULT
      end
    end
  end
end
