module Api
  module V3
    module Subscriptions
      class ExportsController < ApiController
        def show
          render xml: OpmlExport.new(@user, tag: tag).to_xml, content_type: "text/x-opml"
        end

        private

        # A tag the user's feeds have; any other is a 404.
        def tag
          return if params[:tag_id].blank?
          Tag.where(id: @user.taggings.select(:tag_id)).find(params[:tag_id])
        end
      end
    end
  end
end
