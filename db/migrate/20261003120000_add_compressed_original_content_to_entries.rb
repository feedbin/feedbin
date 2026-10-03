class AddCompressedOriginalContentToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :compressed_original_content, :binary
  end
end
