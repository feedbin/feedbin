class Import < ApplicationRecord
  mount_uploader :upload, ImportUploader

  belongs_to :user
  has_many :import_items, dependent: :delete_all

  def process
    ImportWorker.perform_async(id)
  end

  def build_opml_import_job(xml = nil)
    if xml.nil?
      xml = upload.read
    end
    feeds = parse_opml(xml)
    create_tags(feeds)
    feeds.each do |feed|
      import_items << ImportItem.new(details: feed, item_type: "feed")
    end
    update(complete: true) if import_items.empty?
  end

  def parse_opml(xml)
    opml = OpmlSaw::Parser.new(xml)
    opml.parse
    opml.feeds
  end

  def create_tags(feeds)
    tags = Set.new
    feeds.each { |feed| tags.add(feed[:tag]) unless feed[:tag].nil? }
    tags.each { |tag| Tag.where(name: tag).first_or_create! }
  end
end
