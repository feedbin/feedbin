module Api
  module V3
    class Collection
      # Entries joining Recently Read, Recently Played or Airshow's queue,
      # from a body of {ids:, playlist_id:}. Each list has its own rule for
      # who may add an entry; an id that fails it is skipped, not fatal.
      # => {applied: [ids], skipped: [{id:, reason:}]}
      class Additions
        include BodyFields

        MAX_IDS = 1_000

        attr_reader :body

        def initialize(user, collection, body)
          @user = user
          @collection = collection
          @body = body
        end

        def call
          ids = entry_ids
          playlist_id if @collection.id == "queue"
          permissions = EntryAccess.new(@user).permissions_for(ids)
          applied = []
          skipped = []
          ids.each do |id|
            permission = permissions[id]
            reason = if !permission.found? then "not_found"
            elsif !add(permission) then "not_subscribed"
            end
            reason ? skipped << {id: id, reason: reason} : applied << id
          end
          {applied: applied, skipped: skipped}
        end

        private

        def add(permission)
          case @collection.id
          when "recently_read" then add_recently_read(permission)
          when "recently_played" then add_recently_played(permission)
          when "queue" then add_queued(permission)
          end
        end

        def add_recently_read(permission)
          return false unless permission.writable?
          RecentlyReadEntry.create_from_owners(@user, permission.entry.id)
          true
        end

        # Airshow plays episodes of podcasts the reader may not subscribe to,
        # so a podcast subscription or a queued episode is enough, as the
        # web's can_read_entry? allows the queue.
        def add_recently_played(permission)
          @queued_ids ||= @user.queued_entries.pluck(:entry_id).to_set
          return false unless permission.writable? || permission.queueable || @queued_ids.include?(permission.entry.id)
          RecentlyPlayedEntry.create_or_find_by(user_id: @user.id, entry_id: permission.entry.id)
          true
        end

        # Queueing needs the podcast subscription Airshow keeps, not the
        # reader's.
        def add_queued(permission)
          return false unless permission.queueable
          entry = permission.entry
          row = @user.queued_entries.create_with(feed_id: entry.feed_id, playlist_id: playlist_id).create_or_find_by(entry_id: entry.id)
          row.update!(playlist_id: playlist_id) if playlist_id && row.playlist_id != playlist_id
          true
        end

        def entry_ids
          ids = body["ids"]
          unless ids.is_a?(Array) && ids.any? && ids.all? { _1.is_a?(Integer) && _1.positive? }
            raise invalid("ids", "invalid_value", "ids must be an array of entry ids.")
          end
          raise invalid("ids", "too_many", "ids takes at most #{MAX_IDS} ids.") if ids.size > MAX_IDS
          ids.uniq
        end

        # Checked before any id is added, so a bad playlist writes nothing.
        def playlist_id
          return @playlist_id if defined?(@playlist_id)
          id = body["playlist_id"]
          raise invalid("playlist_id", "invalid_value", "playlist_id must be an integer.") unless id.nil? || id.is_a?(Integer)
          raise invalid("playlist_id", "invalid_value", "playlist_id must be one of the user's playlists.") unless id.nil? || @user.playlists.exists?(id: id)
          @playlist_id = id
        end
      end
    end
  end
end
