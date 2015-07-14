module Api
  module V2
    class SuggestedCategoriesController < ApiController

      respond_to :json

      skip_before_action :authorize, only: [:index]

      def index
        @suggested_categories = SuggestedCategory.limit(100)
      end

    end
  end
end
