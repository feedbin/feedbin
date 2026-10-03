class RemoveOriginalFromEntries < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :entries, :original, :json }
  end
end
