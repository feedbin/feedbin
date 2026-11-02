module Api
  module V3
    # The OAuth application behind tokens minted by POST /oauth/development_token,
    # so local clients such as Feedbin Next can sign in without the browser flow.
    # Created by db/seeds.rb and, if it is missing, by the route itself.
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
            owner: owner
          )
      end
    end
  end
end
