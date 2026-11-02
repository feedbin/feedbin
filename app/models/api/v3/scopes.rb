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

      # A token's scopes. One still marked full was minted before the split
      # (by a process running the old code during a deploy) and gets what
      # its app would get now.
      def self.granted(token)
        token.scopes.include?("full") ? self.for(token.application).split : token.scopes.to_a
      end
    end
  end
end
