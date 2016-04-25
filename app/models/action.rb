class Action < ActiveRecord::Base

  attr_accessor :automatic_modification

  belongs_to :user
  enum action_type: { standard: 0, notifier: 1 }

  validate do |action|
    if computed_feed_ids.empty? && self.automatic_modification.blank?
      self.errors[:base] << "Please select at least one feed or tag"
    end
  end

  before_validation :compute_tag_ids
  before_validation :compute_feed_ids
  after_destroy :search_percolate_remove
  after_commit :search_percolate_store, on: [:create, :update]

  def search_percolate_store
    percolator_query = self.query
    percolator_ids = self.computed_feed_ids
    if percolator_ids.empty?
      search_percolate_remove
    elsif empty_notifier_action?
      search_percolate_remove
    else
      Entry.index.register_percolator_query(self.id) do |search|
        search.filtered do
          filter :terms, feed_id: percolator_ids
          unless percolator_query.blank?
            query { string Entry.escape_search(percolator_query) }
          end
        end
      end
    end
  end

  def empty_notifier_action?
    self.all_feeds && self.notifier? && (self.query.nil? || self.query == "")
  end

  def search_percolate_remove
    Entry.index.unregister_percolator_query(self.id)
  end

  def compute_feed_ids
    final_feed_ids = []
    new_feed_ids = self.feed_ids || []
    subscriptions = Subscription.uncached do
      self.user.subscriptions.pluck(:feed_id)
    end
    if self.all_feeds
      final_feed_ids.concat(subscriptions)
    end
    final_feed_ids.concat(self.user.taggings.where(tag: self.tag_ids).pluck(:feed_id))
    final_feed_ids.concat(new_feed_ids.reject(&:blank?).map(&:to_i))
    final_feed_ids = final_feed_ids.uniq
    final_feed_ids = final_feed_ids & subscriptions
    self.computed_feed_ids = final_feed_ids
  end

  def compute_tag_ids
    new_tag_ids = self.tag_ids || []
    new_tag_ids.each do |tag_id|
      if !self.user.tags.where(id: tag_id).present?
        new_tag_ids = new_tag_ids - [tag_id]
      end
    end
    self.tag_ids = new_tag_ids
  end

  def _percolator
    response = Tire::Configuration.client.get "#{Tire::Configuration.url}/_percolator/entries/#{self.id}"
    pp(JSON.load(response.body))
  end

end
