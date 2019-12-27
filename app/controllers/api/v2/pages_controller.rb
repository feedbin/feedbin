module Api
  module V2
    class PagesController < ApiController
      respond_to :json

      def create
        if params[:url]
          @entry = SavePage.new.perform(current_user.id, params[:url], params[:title])
          render status: :created
        else
          status_bad_request([{pages: "Missing required key: url"}])
        end
      end
    end
  end
end
