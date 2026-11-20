module Api
  module V3
    # Turns a supported service on, or changes its setup, from an app's body: an email's name and reply-to, a
    # Kindle's address, Pinboard's or Micro.blog's token checked with the service. One that signs in through the
    # browser is turned on by ShareAuthorization instead.
    class ShareServiceSetup
      include BodyFields

      class TokenRefused < StandardError; end

      attr_reader :body

      def initialize(user, info, body)
        @user = user
        @info = info
        @body = body
      end

      # The saved record; a refused body raises InvalidParameter or TokenRefused.
      def apply
        record = @user.supported_sharing_services.where(service_id: @info.service_id).first_or_initialize
        case ShareServiceCatalog.setup(@info)
        when "email"
          record.email_name = optional_string("email_name")&.strip if body.key?("email_name")
          record.email_address = optional_string("email_address")&.strip if body.key?("email_address")
        when "kindle"
          record.kindle_address = required_string("kindle_address")
        when "token"
          token = required_string("token")
          begin
            answer = @info.klass.constantize.new.request_token(nil, token)
          rescue OAuth::Unauthorized, HTTP::Error
            raise TokenRefused, "#{@info.label} didn't accept the token."
          end
          record.access_token = answer.token
          record.access_secret = answer.secret
        when "none"
          nil
        else
          raise Problems::InvalidParameter.new("#{@info.label} is turned on by signing in through the browser: POST /share_services/#{@info.service_id}/authorization.", pointer: "", code: "authorization_required")
        end
        record.save!
        record.ok!
        record
      end
    end
  end
end
