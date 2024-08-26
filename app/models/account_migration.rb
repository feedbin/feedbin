class AccountMigration < ApplicationRecord
  belongs_to :user
  has_many :account_migration_items
  enum :status, [:pending, :started, :processing, :complete, :failed]

  store :data, accessors: [:fw_streams], coder: JSON

  def percentage_complete
    all = account_migration_items.count
    return 0 if all == 0
    pending = account_migration_items.where.not(status: :pending).count
    (pending.to_f / all.to_f) * 100
  end

  def method_name

  end

  def streams
    fw_streams.safe_dig("streams").filter do |stream|
      stream.safe_dig("search_term").nil? && stream.safe_dig("feeds").count > 0
    end.each_with_object({}) do |stream, streams|
      stream.safe_dig("feeds").each do |feed|
        streams[feed["feed_id"]] ||= []
        streams[feed["feed_id"]].push(stream.safe_dig("title"))
      end
    end
  rescue
    nil
  end
end
