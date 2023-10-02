class AddSiteUrlToImportItems < ActiveRecord::Migration[7.0]
  def change
    add_column :import_items, :site_url, :text
    add_column :import_items, :host, :text
  end
end
