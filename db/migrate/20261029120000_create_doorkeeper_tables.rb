class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      # Public clients (native apps using PKCE) have no secret.
      t.string :secret
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.references :owner, polymorphic: true, null: false
      t.timestamps
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner, null: false
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_grants, :token, unique: true

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.string :device_name
      t.datetime :last_used_at
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
