class Import < ApplicationRecord
  belongs_to :user
  has_many :import_items, dependent: :delete_all
  before_validation :parse

  validate do |import|
    import.errors.add(:base, "No feeds found") if import.import_items.empty?
  end

  attr_accessor :xml

  def parse
    feeds = Opml::Parser.parse(xml)
    create_tags(feeds)

    feeds = flatten_feeds(feeds)
    feeds.each do |feed|
      import_items << ImportItem.new(details: feed)
    end
  end

  def create_tags(feeds)
    tags = feeds.filter_map { _1[:tag] }.uniq
    tags.each { |tag| Tag.where(name: tag).first_or_create! }
  end

  def flatten_feeds(feeds)
    feeds.each_with_object({}) do |feed, hash|
      hash[feed[:xml_url]] ||= feed.merge({tags: []})
      if feed[:tag]
        hash[feed[:xml_url]][:tags].push(feed[:tag])
      end
    end.map do |_, feed|
      tags = feed.delete(:tags)
      if !tags.empty?
        feed[:tag] = tags.join(",")
      end
      feed
    end
  end

  def percentage
    all = import_items.count
    return 0 if all == 0
    pending = import_items.where.not(status: :pending).count
    (pending.to_f / all.to_f) * 100
  end

  def percentage_failed
    all = import_items.count
    return 0 if all == 0
    failed = import_items.failed.count
    (failed.to_f / all.to_f) * 100
  end

  def percentage_complete
    all = import_items.count
    return 0 if all == 0
    complete = import_items.complete.count
    (complete.to_f / all.to_f) * 100
  end

  def percentage_fixable
    all = import_items.count
    return 0 if all == 0
    complete = import_items.fixable.count
    (complete.to_f / all.to_f) * 100
  end
end
