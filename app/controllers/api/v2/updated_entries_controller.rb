module Api
  module V2
    class UpdatedEntriesController < ApiController
      respond_to :json

      def index
        @user = current_user
        entries = @user.updated_entries.order(updated_at: :desc)
        if params[:since]
          time = Time.iso8601(params[:since])
          entries = entries.where("updated_entries.updated_at > :time", {time: time})
        end
        render json: entries.limit(100).pluck(:entry_id).compact.to_json
      end

      def destroy
        @user = current_user
        @user.updated_entries.where(entry_id: params[:updated_entries]).delete_all
        render json: params[:updated_entries].to_json
      end
    end
  end
end
