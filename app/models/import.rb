class Import < ApplicationRecord
  belongs_to :user
  has_many :import_items, dependent: :delete_all
  before_create :parse

  attr_accessor :xml

  def parse
    feeds = Opml::Parser.parse(xml)
    create_tags(feeds)
    feeds.each do |feed|
      import_items << ImportItem.new(details: feed)
    end
    complete = true if import_items.empty?
  end

  def create_tags(feeds)
    tags = Set.new
    feeds.each { |feed| tags.add(feed[:tag]) unless feed[:tag].nil? }
    tags.each { |tag| Tag.where(name: tag).first_or_create! }
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
    failed = import_items.where(status: :failed).count
    (failed.to_f / all.to_f) * 100
  end

  def percentage_complete
    all = import_items.count
    return 0 if all == 0
    complete = import_items.where(status: :complete).count
    (complete.to_f / all.to_f) * 100
  end
end
