class AddStatusToSupportedSharingServices < ActiveRecord::Migration[7.0]
  def change
    add_column :supported_sharing_services, :status, :bigint, default: 0, null: false
  end
end
