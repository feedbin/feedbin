class AddOriginalUserIdToDeletedUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :deleted_users, :original_user_id, :bigint
  end
end
