class AddOriginalFingerprintToImages < ActiveRecord::Migration[8.1]
  def change
    add_column :images, :original_fingerprint, :uuid
  end
end
