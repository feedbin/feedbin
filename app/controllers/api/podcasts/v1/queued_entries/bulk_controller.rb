module Api
  module Podcasts
    module V1
      class QueuedEntries::BulkController < ApiController
        before_action :set_queued_entries, only: [:update]
        before_action :validate_content_type, only: [:update]
        wrap_parameters QueuedEntry

        def update
          @queued_entries.each do |queued_entry|
            next unless update_params = params[:queued_entries].find { |entry| entry[:id] == queued_entry.entry_id }
            filtered_params = update_params.permit(:order, :progress)
            update_params = remove_stale_updates(queued_entry, filtered_params, update_params)
            queued_entry.update(update_params)
          end

          head :no_content
        end

        private

        def set_queued_entries
          @queued_entries = @user.queued_entries.where(entry_id: params[:queued_entries].map { |entry| entry[:id] })
        end
      end
    end
  end
end