class AccountMigrationItem < ApplicationRecord
  belongs_to :account_migration

  after_commit :process, on: :create

  enum :status, [:pending, :complete, :failed]

  store :data, accessors: [:fw_feed], coder: JSON

  def process
    AccountMigrator::ImportFeed.perform_async(id)
  end
end
