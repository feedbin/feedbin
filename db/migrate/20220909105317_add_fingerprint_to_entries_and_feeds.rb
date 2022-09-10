class AddFingerprintToEntriesAndFeeds < ActiveRecord::Migration[7.0]
  def change
    add_column :feeds, :fingerprint, :uuid
    add_column :entries, :fingerprint, :uuid
    add_column :entries, :guid, :uuid
  end
end
