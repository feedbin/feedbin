class UseTextForEntryId < ActiveRecord::Migration[4.2]
  def up
    change_table :entries do |t|
      t.change :entry_id, :text
    end
  end

  def down
    change_table :entries do |t|
      t.change :entry_id, :string
    end
  end
end
