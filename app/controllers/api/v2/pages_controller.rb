module Api
  module V2
    class PagesController < ApiController
      respond_to :json

      def create
        status_too_many_requests and return if rate_limited?(100, 1.day)
        if params[:url]
          @entry = SavePage.new.perform(current_user.id, params[:url], params[:title])
          render status: :created
        else
          status_bad_request([{pages: "Missing required key: url"}])
        end
      rescue SavePage::MissingPage => exception
        SavePage.perform_async(current_user.id, params[:url], params[:title])
        @entry = exception.entry
        render status: :created
      end
    end
  end
end
