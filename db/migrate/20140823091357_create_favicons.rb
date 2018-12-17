class CreateFavicons < ActiveRecord::Migration[4.2]
  def change
    create_table :favicons do |t|
      t.text :host
      t.text :favicon
      t.timestamps
    end
    add_index :favicons, :host, unique: true
  end
end
