class ImportItem < ActiveRecord::Base
  serialize :details, Hash
  belongs_to :import

  after_commit(on: :create) do
    FeedImporter.perform_async(self.id)
  end
end
