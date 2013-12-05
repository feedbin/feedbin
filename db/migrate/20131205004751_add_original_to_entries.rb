class AddOriginalToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :original, :json
  end
end
