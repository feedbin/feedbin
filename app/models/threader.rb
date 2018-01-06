class Threader

  def initialize(entry_hash, feed)
    @entry_hash = ActiveSupport::HashWithIndifferentAccess.new(entry_hash)
    @feed = feed
    @thread_id = @entry_hash["thread_id"]
    @reply_to = @entry_hash.dig("data", "tweet", "in_reply_to_status_id")
  end

  def thread
    if entry = parent_entry
      updated_thread = entry.thread.push(@entry_hash["data"]["tweet"])
      entry.data["thread"] = updated_thread
      entry.thread_id = @thread_id
      entry.save!
    end
  rescue => e
    Honeybadger.notify(e)
    false
  end


  def parent_entry
    @parent_entry ||= begin
      entry = false
      if @thread_id && @reply_to
        if parent_entry = @feed.entries.where(thread_id: @reply_to)
          if parent_entry.length == 1
            entry = parent_entry.first
          end
        end
      end
      entry
    end
  end

end
