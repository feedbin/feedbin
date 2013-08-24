class AddAttachmentFileToImports < ActiveRecord::Migration
  def self.up
    change_table :imports do |t|
      t.has_attached_file :file
    end
  end

  def self.down
    drop_attached_file :imports, :file
  end
end
