class RemoveFileFromImports < ActiveRecord::Migration
  def self.up
    drop_attached_file :imports, :file
  end

  def self.down
    change_table :imports do |t|
      t.has_attached_file :file
    end
  end
end
