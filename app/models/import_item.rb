class ImportItem < ApplicationRecord
  serialize :details, Hash
  belongs_to :import

  after_commit :import_feed, on: :create

  enum status: [:pending, :complete, :failed]

  def import_feed
    FeedImporter.perform_async(id)
  end
end
