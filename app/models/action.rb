class Action < ApplicationRecord
  attr_accessor :automatic_modification, :apply_action

  belongs_to :user
  enum :action_type, {standard: 0, notifier: 1, mute: 2}
  enum :status, {active: 0, suspended: 1, broken: 2}

  validate do |action|
    if computed_feed_ids.empty? && automatic_modification.blank?
      action.errors.add :base, "Please select at least one feed or tag"
    end
  end

  before_validation :compute_tag_ids
  before_validation :compute_feed_ids

  validate :query_valid, unless: :automatic_modification
  validates :query, presence: true, if: -> { mute? }

  after_destroy :percolate_destroy
  after_commit :percolate_create, on: [:create, :update]
  after_commit :bulk_actions, on: [:create, :update]

  before_save :record_status

  def record_status
    if automatic_modification.blank?
      self.status = Action.statuses[:active]
    end
  end

  def percolate_create
    Search::PercolateCreate.perform_async(id)
  end

  def percolate_destroy
    Search::PercolateDestroy.perform_async(id)
  end

  def bulk_actions
    Search::ActionsBulk.perform_async(id, user.id) if apply_action == "1"
  end

  def search_body
    {}.tap do |hash|
      hash[:feed_id] = computed_feed_ids
      hash[:query] = {
        bool: {
          filter: {
            bool: {
              must: {terms: {feed_id: computed_feed_ids}}
            }
          }
        }
      }
      if query.present?
        escaped_query = Entry.escape_search(query)
        hash[:query][:bool][:must] = {
          query_string: {
            fields: ["title", "title.*", "content", "content.*", "author", "url", "link"],
            default_operator: "AND",
            query: escaped_query
          }
        }
      end
    end
  end

  def compute_feed_ids
    final_feed_ids = []
    new_feed_ids = feed_ids || []
    subscriptions = Subscription.uncached {
      user.subscriptions.pluck(:feed_id)
    }
    if all_feeds
      final_feed_ids.concat(subscriptions)
    end
    final_feed_ids.concat(user.taggings.where(tag: tag_ids).pluck(:feed_id))
    final_feed_ids.concat(new_feed_ids.reject(&:blank?).map(&:to_i))
    final_feed_ids = final_feed_ids.uniq
    final_feed_ids &= subscriptions
    self.computed_feed_ids = final_feed_ids
  end

  def compute_tag_ids
    new_tag_ids = tag_ids || []
    new_tag_ids.each do |tag_id|
      unless user.tags.where(id: tag_id).present?
        new_tag_ids -= [tag_id]
      end
    end
    self.tag_ids = new_tag_ids
  end

  def query_valid
    result = Search.client { _1.validate(Entry.table_name, query: {query: search_body[:query]}) }
    if result == false
      errors.add :base, "Search syntax invalid"
    end
  end

  def results
    response = Search.client { _1.search(Entry.table_name, query: search_options) }
    OpenStruct.new({total: response.total, records: response.records(Entry).includes(:feed)})
  end

  def error_hint
    @error_hint ||= begin
      if valid?
        ""
      else
        "Invalid Action: #{errors.full_messages.to_sentence(words_connector: ".")}"
      end
    end
  end

  def search_options
    {}.tap do |hash|
      hash[:query] = search_body[:query]
      hash[:sort] = [{published: "desc"}]
    end
  end

  def _percolator
    Search.client { _1.get(Action.table_name, id: id) }
  end
end
