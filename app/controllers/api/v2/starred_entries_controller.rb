module Api
  module V2
    class StarredEntriesController < ApiController

      respond_to :json

      before_action :validate_content_type, only: [:create]
      before_action :validate_create, only: [:create]

      def index
        @user = current_user
        render json: @user.starred_entries.pluck(:entry_id).compact.to_json
      end

      def create
        @user = current_user
        entries = get_valid_entries
        ActiveRecord::Base.transaction do
          entries[:valid_entries].each do |entry|
            StarredEntry.create(user_id: @user.id, feed_id: entry[:feed_id], entry_id: entry[:entry_id], published: entry[:published])
          end
        end
        render json: entries[:entry_ids].to_json
      end

      def destroy
        @user = current_user
        entries = get_valid_entries
        StarredEntry.where(user_id: @user.id, entry_id: entries[:entry_ids]).destroy_all
        render json: entries[:entry_ids].to_json
      end

      private

      def get_valid_entries
        @user = current_user

        user_feeds = @user.subscriptions.pluck(:feed_id)

        user_starred = @user.starred_entries.pluck(:entry_id)
        entry_feeds = Entry.where(id: params[:starred_entries]).pluck(:id, :feed_id, :published)

        valid_entries = []
        entry_feeds.each do |entry_id, feed_id, published|
          if user_feeds.include?(feed_id) || user_starred.include?(entry_id)
            valid_entries << {entry_id: entry_id, feed_id: feed_id, published: published}
          end
        end
        entry_ids = valid_entries.map {|entry| entry[:entry_id]}

        {valid_entries: valid_entries, entry_ids: entry_ids}
      end

      def validate_create
        needs 'starred_entries'

        if params[:starred_entries].respond_to?(:count)
          if params[:starred_entries].count > 1000
            status_bad_request([{starred_entries: 'Please send less than or equal to 1,000 ids per request'}])
          end
        end
      end

    end
  end
end
