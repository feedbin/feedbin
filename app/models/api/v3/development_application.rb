module Api
  module V3
    # The OAuth application behind POST /oauth/development_token tokens.
    class DevelopmentApplication
      CLIENT_ID = "feedbin-next-development"
      REDIRECT_URI = "feedbin-next://oauth/callback"
      NAME = "Feedbin Next (development)"

      def self.ensure!(owner:)
        Doorkeeper::Application.find_by(uid: CLIENT_ID) ||
          Doorkeeper::Application.create!(
            uid: CLIENT_ID,
            name: NAME,
            redirect_uri: REDIRECT_URI,
            confidential: false,
            scopes: Scopes::FIRST_PARTY,
            owner: owner
          )
      end
    end
  end
end
