module Api
  module V3
    module Imports
      module Items
        # One fixable feed replaced, in the background, with a feed found at its site: `suggestion_id`, one of the
        # item's `suggestions`, or the first. The import answers with the item pending.
        class ReplacementsController < ApiController
          include BodyFields
          include ImportScoped

          before_action :set_import, :set_import_item, :ensure_fixable

          def create
            @import_item.replace(suggestion)
            render_import(status: :accepted)
          end

          private

          def set_import_item
            @import_item = @import.import_items.find(params[:item_id])
          end

          def ensure_fixable
            raise invalid("", "invalid_value", "Only a fixable feed can be replaced.") unless @import_item.fixable?
          end

          def suggestion
            return if body["suggestion_id"].nil?
            id = body["suggestion_id"]
            @import_item.discovered_feeds.find { it.id == id } or raise invalid("suggestion_id", "invalid_value", "suggestion_id must be one of the item's suggestions.")
          end
        end
      end
    end
  end
end
