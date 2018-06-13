class AddOriginalToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :original, :json
  end
end
