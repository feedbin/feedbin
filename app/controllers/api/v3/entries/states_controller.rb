module Api
  module V3
    module Entries
      class StatesController < ApiController
        def create
          render json: StateChange.new(@user, body).call
        end
      end
    end
  end
end
