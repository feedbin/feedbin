class CreateAttributeChanges < ActiveRecord::Migration[7.0]
  def change
    create_table :attribute_changes do |t|
      t.belongs_to :trackable, polymorphic: true, index: false
      t.text :name
      t.timestamps
    end
    add_index :attribute_changes, [:trackable_id, :trackable_type, :name], unique: true, name: :index_attribute_changes_on_trackable_and_name
  end
end
