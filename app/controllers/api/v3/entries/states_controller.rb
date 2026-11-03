module Api
  module V3
    module Entries
      # POST /entries/state: the state verbs (see StateChange).
      class StatesController < ApiController
        def create
          render json: StateChange.new(@user, body).call
        end
      end
    end
  end
end
