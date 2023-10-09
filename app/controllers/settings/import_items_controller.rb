module Settings
  class ImportItemsController < ApplicationController
    def update
      @user = current_user
      @import_item = @user.import_items.find(params[:id])
      @import_item.complete!
      FeedImportFixer.perform_async(@user.id, @import_item.id, params[:discovered_feed][:id].to_i)
    end
  end
end
