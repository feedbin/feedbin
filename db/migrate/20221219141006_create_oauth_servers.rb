class CreateOauthServers < ActiveRecord::Migration[7.0]
  def change
    create_table :oauth_servers do |t|
      t.text :host, null: false, index: {unique: true}
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end
  end
end
