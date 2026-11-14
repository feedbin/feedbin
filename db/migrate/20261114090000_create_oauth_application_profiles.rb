# What an application's owner says about it, kept beside Doorkeeper's own
# table instead of in it. The logo is an object in the image store.
class CreateOauthApplicationProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_application_profiles do |t|
      t.references :application, null: false, index: {unique: true}, foreign_key: {to_table: :oauth_applications, on_delete: :cascade}
      t.text :description
      t.string :url
      t.string :contact_email
      t.string :logo_storage_path
      t.timestamps
    end
  end
end
