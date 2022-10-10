class ImportItem < ApplicationRecord
  serialize :details, Hash
  belongs_to :import
  enum status: [:pending, :complete, :failed]
  store_accessor :error, :class, :message, prefix: true

  after_commit :import_feed, on: :create

  def import_feed
    FeedImporter.perform_async(id)
  end
end
