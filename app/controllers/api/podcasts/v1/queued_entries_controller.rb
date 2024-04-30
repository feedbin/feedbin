module Api
  module Podcasts
    module V1
      class QueuedEntriesController < ApiController
        before_action :set_queued_entry, only: [:update, :destroy]
        before_action :validate_content_type, only: [:create, :update]

        def index
          @user = current_user
          @queued_entries = @user.queued_entries
        end

        def create
          entry_id = params[:entry_id]
          entry = Entry.find(entry_id)

          if @user.podcast_subscriptions.where(feed: entry.feed).exists?
            @queued_entry = @user.queued_entries.create_with(feed_id: entry.feed_id).find_or_create_by(entry_id: entry.id)
            @queued_entry.update(queued_entry_params)
          else
            status_forbidden
          end
        end

        def destroy
          @queued_entry.destroy
          head :no_content
        end

        def update
          update_params = remove_stale_updates(@queued_entry, queued_entry_params, params)
          @queued_entry.update(update_params)
          head :no_content
        end

        private

        def queued_entry_params
          params.require(:queued_entry).permit(:order, :progress, :duration, :playlist_id, skipped_chapters: [])
        end

        def set_queued_entry
          @queued_entry = @user.queued_entries.find_by_entry_id!(params[:id])
        end
      end
    end
  end
end