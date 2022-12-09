class AddProfileImageUrlToTwitterUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :twitter_users, :profile_image_url, :text
  end
end
