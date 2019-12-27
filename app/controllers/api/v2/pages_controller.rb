module Api
  module V2
    class PagesController < ApiController
      respond_to :json

      def create
        @entry = SavePage.new.perform(current_user.id, params[:url], params[:title])
        render status: :created
      end
    end
  end
end
