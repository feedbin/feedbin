class ImportItem < ApplicationRecord
  serialize :details, Hash
  belongs_to :import

  after_commit(on: :create) do
    FeedImporter.perform_async(id)
  end
end
