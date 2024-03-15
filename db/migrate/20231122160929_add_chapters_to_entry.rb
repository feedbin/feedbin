class AddChaptersToEntry < ActiveRecord::Migration[7.1]
  def change
    add_column :entries, :chapters, :jsonb
  end
end
