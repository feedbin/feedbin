module Api
  module V3
    module ShareServices
      # The page an app opens to connect a service that signs in through the browser. When the user is done, the
      # service's callback sends the browser to `return_to`, with `service_id` and `status` (`active`, `declined`,
      # `failed`) in its query.
      class AuthorizationsController < ApiController
        include BodyFields
        include ShareServiceScoped

        before_action :set_share_service, :ensure_browser_sign_in

        def create
          url = ShareAuthorization.start(@user, @info.service_id, return_to: return_to, mastodon_host: mastodon_host)
          render json: {object: "share_authorization", service_id: @info.service_id, authorize_url: url}, status: :created
        rescue ShareAuthorization::Invalid, Share::Service::AuthError, OAuth::Error, HTTP::Error => error
          render_problem :unprocessable_content, "authorization_failed", title: "Authorization failed", detail: error.message
        end

        private

        def ensure_browser_sign_in
          return if %w[oauth server].include?(ShareServiceCatalog.setup(@info))
          raise Problems::InvalidParameter.new("#{@info.label} doesn't sign in through the browser.", pointer: "", code: "invalid_value")
        end

        # Only the app's own address: one with the scheme its OAuth redirect has, so a token can't send the browser
        # anywhere else.
        def return_to
          value = required_string("return_to")
          scheme = URI.parse(value).scheme rescue nil
          schemes = @token.application&.redirect_uri.to_s.split.filter_map { URI.parse(_1).scheme rescue nil }
          unless scheme.present? && !%w[http https].include?(scheme.downcase) && schemes.include?(scheme)
            raise invalid("return_to", "invalid_value", "return_to must be this app's own address.")
          end
          value
        end

        def mastodon_host
          @info.service_id == "mastodon" ? required_string("mastodon_host") : nil
        end
      end
    end
  end
end
