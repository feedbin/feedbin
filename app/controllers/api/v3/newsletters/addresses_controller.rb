module Api
  module V3
    module Newsletters
      class AddressesController < ApiController
        before_action :set_address, only: :update

        def index
          data = addresses.order(:created_at, :id).map { NewsletterAddressSerializer.new(it).to_h }
          return unless stale?(etag: digest(data))
          render_list(data)
        end

        # A proposal, as Find feeds is for subscriptions: nothing is stored.
        def new
          token = AuthenticationToken.newsletters.generate_custom_token(proposal_prefix) or return status_prefix_unavailable
          render json: {
            object: "newsletter_address_proposal",
            address: AuthenticationToken.newsletters.new(token: token).title,
            token: token,
            verified_token: AuthenticationToken.address_verifier.generate(token)
          }
        end

        def create
          attributes = address_params
          attributes[:token] = verified_token if body.key?("verified_token")
          address = addresses.create!(attributes)
          render json: NewsletterAddressSerializer.new(address).to_h, status: :created
        rescue ActiveRecord::RecordNotUnique
          status_prefix_unavailable
        end

        def update
          @address.update!(address_params)
          render json: NewsletterAddressSerializer.new(@address).to_h
        end

        private

        def addresses
          @user.authentication_tokens.newsletters
        end

        def set_address
          @address = addresses.find(params[:id])
        end

        def proposal_prefix
          prefix = AuthenticationToken.newsletter_prefix(required_string("prefix"))
          raise invalid("prefix", "invalid_value", "prefix must have a letter, digit, -, . or _.") if prefix.empty?
          prefix
        end

        def verified_token
          token = AuthenticationToken.address_verifier.verified(optional_string("verified_token").to_s)
          raise invalid("verified_token", "invalid_value", "verified_token is not one POST /newsletters/addresses/new returned.") unless token.is_a?(String)
          token
        end

        # Blank text is stored as nil: the receiver falls back to the
        # account's tag only when the address's is nil.
        def address_params
          attributes = {}
          attributes[:description] = optional_string("description", detail: "description must be a string or null.")&.strip.presence if body.key?("description")
          attributes[:newsletter_tag] = optional_string("default_tag", detail: "default_tag must be a string or null.")&.strip.presence if body.key?("default_tag")
          attributes[:active] = boolean("active") if action_name == "update" && body.key?("active")
          attributes
        end

        def status_prefix_unavailable
          render_problem :unprocessable_content, "prefix_unavailable",
            title: "Prefix unavailable",
            detail: "Every address with this prefix is taken. Try another prefix."
        end
      end
    end
  end
end
