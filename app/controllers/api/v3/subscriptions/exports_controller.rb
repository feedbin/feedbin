module Api
  module V3
    module Subscriptions
      class ExportsController < ApiController
        def show
          render xml: OpmlExport.new(@user).to_xml, content_type: "text/x-opml"
        end
      end
    end
  end
end
