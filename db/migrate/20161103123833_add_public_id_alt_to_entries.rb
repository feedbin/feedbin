class AddPublicIdAltToEntries < ActiveRecord::Migration[5.0]
  def change
    add_column :entries, :public_id_alt, :string
  end
end
