module Search
  class ActionsBulk
    include Sidekiq::Worker
    sidekiq_options queue: :network_search, retry: false

    def perform(action_id, user_id)
      user   = User.find(user_id)
      action = user.actions.find(action_id)
      ids    = Search::Client.all_matches(Entry.table_name, query: action.search_options)

      if action.actions.include?("mark_read") && ids.present?
        user.unread_entries.where(entry_id: ids).delete_all
      end
    end
  end
end