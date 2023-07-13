class CreateRUsersProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :r_users_profiles do |t|
      t.references :user, foreign_key: true, null: false
      t.references :profile, foreign_key: true, null: false
    end
  end
end
