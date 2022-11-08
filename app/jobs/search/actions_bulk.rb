module Search
  class ActionsBulk
    include Sidekiq::Worker
    sidekiq_options queue: :network_search, retry: false

    def perform(action_id, user_id)
      user = User.find(user_id)
      action = user.actions.find(action_id)

      result = Search::Client.search(Entry.table_name, query: action.search_options)
      entry_ids = result.ids
      if result.pagination.total_pages > 1
        2.upto(result.pagination.total_pages) do |page|
          result = Search::Client.search(Entry.table_name, query: action.search_options, page: page)
          entry_ids = entry_ids.concat(result.ids)
        end
      end

      action.actions.include?("mark_read").each do |task|
        user.unread_entries.where(entry_id: entry_ids).delete_all
      end
    end
  end
end