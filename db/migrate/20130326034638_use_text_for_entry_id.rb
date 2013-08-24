class UseTextForEntryId < ActiveRecord::Migration
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
