class AddStandaloneRequestAtToFeed < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :feeds, :standalone_request_at, :datetime
    add_index :feeds, :standalone_request_at, where: "standalone_request_at IS NOT NULL", order: {standalone_request_at: :desc}, algorithm: :concurrently
  end
end
