class Action < ActiveRecord::Base

    attr_accessor :empty, :automatic_modification

    belongs_to :user

    validate do |action|
      if computed_feed_ids.empty? && self.automatic_modification.blank?
        self.errors[:base] << "Please select at least one feed or tag"
      end
    end

    before_validation :compute_tag_ids
    before_validation :compute_feed_ids
    before_save :check_if_empty
    after_destroy :search_percolate_remove

    after_commit :search_percolate_store, on: [:create, :update]

    enum action_type: { standard: 0, notifier: 1 }

    def search_percolate_store
      if self.empty == true && self.automatic_modification == true
        self.destroy
      else
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
    end

    def search_percolate_remove
      Entry.index.unregister_percolator_query(self.id)
    end

    def compute_feed_ids
      final_feed_ids = []
      if self.all_feeds
        subscriptions = Subscription.uncached do
          self.user.subscriptions.pluck(:feed_id)
        end
        final_feed_ids.concat(subscriptions)
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

    def check_if_empty
      if self.computed_feed_ids.empty? && !self.computed_feed_ids_was.empty?
        self.empty = true
      end
    end

end
