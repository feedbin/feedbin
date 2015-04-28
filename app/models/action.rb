class Action < ActiveRecord::Base
    belongs_to :user

    before_save :compute_tag_ids
    before_save :compute_feed_ids
    after_commit :search_percolate_store, on: [:create, :update]
    after_destroy :search_percolate_remove

    enum action_type: { standard: 0, notifier: 1 }

    def search_percolate_store
      action_feed_ids = self.computed_feed_ids
      action_query = self.query
      result = Entry.index.register_percolator_query(self.id) do |search|
        search.filtered do
          unless action_query.blank?
            query { string Entry.escape_search(action_query) }
          end
          if action_feed_ids.any?
            filter :terms, feed_id: action_feed_ids
          end
        end
      end
      if result.nil?
        Honeybadger.notify(
          error_class: "Action Percolate Save",
          error_message: "Action Percolate Save Failure",
          parameters: {id: self.id}
        )
      end
    end

    def search_percolate_remove
      Entry.index.unregister_percolator_query(self.id)
    end

    def compute_feed_ids
      final_feed_ids = []
      if self.all_feeds
        final_feed_ids.concat(self.user.subscriptions.pluck(:feed_id))
      end
      final_feed_ids.concat(self.user.taggings.where(tag: self.tag_ids).pluck(:feed_id))
      final_feed_ids.concat(self.feed_ids.reject(&:blank?).map(&:to_i))
      final_feed_ids = final_feed_ids.uniq
      self.computed_feed_ids = final_feed_ids
    end

    def compute_tag_ids
      self.tag_ids.each do |tag_id|
        if !self.user.tags.where(id: tag_id).present?
          self.tag_ids = self.tag_ids - [tag_id]
        end
      end
    end

end
