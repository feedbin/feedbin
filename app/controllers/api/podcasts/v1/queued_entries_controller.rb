module Api
  module Podcasts
    module V1
      class QueuedEntriesController < ApiController
        before_action :set_queued_entry, only: [:destroy]
        before_action :validate_content_type, only: [:create]

        def index
          @user = current_user
          @queued_entries = @user.queued_entries
        end

        def create
          entry_id = queued_entry_params[:entry_id]
          if @user.can_read_entry?(entry_id)
            entry = Entry.find(entry_id)
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

        private

        def queued_entry_params
          params.require(:queued_entry).permit(:entry_id, :order, :progress)
        end

        def set_queued_entry
          @queued_entry = @user.queued_entries.find(params[:id])
        end
      end
    end
  end
end