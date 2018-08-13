module Api
  module V2
    class RecentlyReadEntriesController < ApiController
      respond_to :json

      def index
        @user = current_user
        render json: @user.recently_read_entries.order(created_at: :desc).limit(100).pluck(:entry_id).compact.to_json
      end

      def create
        @user = current_user
        params[:recently_read_entries].each do |entry_id|
          @user.recently_read_entries.create!(entry_id: entry_id)
        end
        render json: params[:recently_read_entries].to_json
      end
    end
  end
end
