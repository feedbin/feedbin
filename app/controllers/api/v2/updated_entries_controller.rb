module Api
  module V2
    class UpdatedEntriesController < ApiController
      respond_to :json

      def index
        @user = current_user
        render json: @user.updated_entries.order(updated_at: :desc).limit(100).pluck(:entry_id).compact.to_json
      end

      def destroy
        @user = current_user
        @user.updated_entries.where(entry_id: params[:updated_entries]).delete_all
        render json: params[:updated_entries].to_json
      end
    end
  end
end
