class CreateOauthApplicationLogos < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_application_logos do |t|
      t.references :application, null: false, index: {unique: true}, foreign_key: {to_table: :oauth_applications, on_delete: :cascade}
      t.binary :data, null: false
      t.timestamps
    end
  end
end
