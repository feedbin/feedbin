module Api
  module V3
    module CollectionScoped
      extend ActiveSupport::Concern

      included do
        before_action :set_collection
      end

      private

      def set_collection
        @collection = Collection.find(@user, params[:collection_id]) or raise ActiveRecord::RecordNotFound
      end

      def ensure_collection_accepts(write)
        return if @collection.accepts?(write)
        raise Problems::InvalidParameter.new("The #{@collection.id} collection does not accept #{write}.", pointer: "id", code: "invalid_value")
      end
    end
  end
end
