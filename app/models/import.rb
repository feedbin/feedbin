class Import < ApplicationRecord
  mount_uploader :upload, ImportUploader

  belongs_to :user
  has_many :import_items, dependent: :delete_all

  after_save :enqueue_processing

  def enqueue_processing
    ImportWorker.perform_async(id)
  end

  def build_opml_import_job
    feeds = parse_opml
    create_tags(feeds)
    feeds.each do |feed|
      import_items << ImportItem.new(details: feed, item_type: "feed")
    end
  end

  def parse_opml
    contents = upload.read
    opml = OpmlSaw::Parser.new(contents)
    opml.parse
    opml.feeds
  end

  def create_tags(feeds)
    tags = Set.new
    feeds.each { |feed| tags.add(feed[:tag]) unless feed[:tag].nil? }
    tags.each { |tag| Tag.where(name: tag).first_or_create! }
  end
end
