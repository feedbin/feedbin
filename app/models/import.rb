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
end
