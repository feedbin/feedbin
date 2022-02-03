module Api
  module Public
    module V1
      class ApiController < ApplicationController
        respond_to :json
        skip_before_action :verify_authenticity_token
        skip_before_action :authorize
        skip_before_action :set_user

        private

        def hex_decode(string)
          string.scan(/../).map { |x| x.hex.chr }.join
        end

      end
    end
  end
end
