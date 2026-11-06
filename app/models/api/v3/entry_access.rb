module Api
  module V3
    # Writable means subscribed to the entry's feed or starred.
    class EntryAccess
      Permission = Struct.new(:entry, :subscribed, :starred, :unread, :queueable) do
        def found? = !entry.nil?
        def writable? = subscribed || starred
        def reason = found? ? (writable? ? nil : "not_subscribed") : "not_found"
      end

      def initialize(user)
        @user = user
      end

      # => {id => Permission}
      def permissions_for(ids)
        entries = Entry.where(id: ids).select(:id, :feed_id, :published, :created_at).index_by(&:id)
        feed_ids = entries.values.map(&:feed_id).uniq
        subscribed = @user.subscriptions.where(feed_id: feed_ids).pluck(:feed_id).to_set
        podcasts = @user.podcast_subscriptions.where(feed_id: feed_ids).pluck(:feed_id).to_set
        starred = @user.starred_entries.where(entry_id: ids).pluck(:entry_id).to_set
        unread = @user.unread_entries.where(entry_id: ids).pluck(:entry_id).to_set

        ids.index_with do |id|
          entry = entries[id]
          Permission.new(entry, entry && subscribed.include?(entry.feed_id), starred.include?(id), unread.include?(id), entry && podcasts.include?(entry.feed_id))
        end
      end
    end
  end
end
