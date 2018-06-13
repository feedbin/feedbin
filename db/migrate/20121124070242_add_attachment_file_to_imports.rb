class AddAttachmentFileToImports < ActiveRecord::Migration[4.2]
  def self.up
    change_table :imports do |t|
      t.has_attached_file :file
    end
  end

  def self.down
    drop_attached_file :imports, :file
  end
end
