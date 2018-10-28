class Action < ApplicationRecord
  attr_accessor :automatic_modification, :apply_action

  belongs_to :user
  enum action_type: {standard: 0, notifier: 1}

  validate do |action|
    if computed_feed_ids.empty? && self.automatic_modification.blank?
      self.errors[:base] << "Please select at least one feed or tag"
    end
  end

  before_validation :compute_tag_ids
  before_validation :compute_feed_ids

  validate :query_valid, unless: :automatic_modification

  after_destroy :percolate_destroy
  after_commit :percolate_create, on: [:create, :update]
  after_commit :bulk_actions, on: [:create, :update]

  def percolate_create
    PercolateCreate.perform_async(self.id)
  end

  def percolate_destroy
    PercolateDestroy.perform_async(self.id)
  end

  def bulk_actions
    ActionsBulk.perform_async(self.id, self.user.id) if apply_action == "1"
  end

  def search_body
    Hash.new.tap do |hash|
      hash[:feed_id] = self.computed_feed_ids
      hash[:query] = {
        bool: {
          filter: {
            bool: {
              must: {terms: {feed_id: self.computed_feed_ids}},
            },
          },
        },
      }
      if self.query.present?
        escaped_query = FeedbinUtils.escape_search(self.query)
        hash[:query][:bool][:must] = {
          query_string: {
            fields: ["title", "content", "emoji", "author", "url"],
            default_operator: "AND",
            query: escaped_query,
          },
        }
        if !escaped_query.include?("title.exact") && !escaped_query.include?("content.exact")
          hash[:query][:bool][:must][:query_string][:quote_field_suffix] = ".exact"
        end
      end
    end
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
    Entry.__elasticsearch__.client.get(
      index: Entry.index_name,
      type: ".percolator",
      id: self.id,
      ignore: 404,
    )
  end

  def query_valid
    options = {
      index: Entry.index_name,
      body: {query: search_body[:query]},
    }
    result = $search[:main].indices.validate_query(options)
    if false == result["valid"]
      self.errors[:base] << "Search syntax invalid"
    end
  end

  def results
    Entry.search(search_options).page(1).records(includes: :feed)
  end

  def scrolled_results(&block)
    scroll = "2m"
    response = Entry.__elasticsearch__.client.search(
      index: Entry.index_name,
      type: Entry.document_type,
      scroll: scroll,
      body: search_options,
    )

    while response["hits"]["hits"].any?
      yield response
      response = Entry.__elasticsearch__.client.scroll({scroll_id: response["_scroll_id"], scroll: scroll})
    end

    return response["_scroll_id"]
  end

  private

  def search_options
    Hash.new.tap do |hash|
      hash[:query] = search_body[:query]
      hash[:sort] = [{published: "desc"}]
    end
  end
end
