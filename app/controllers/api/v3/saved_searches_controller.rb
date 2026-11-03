module Api
  module V3
    # Saved searches: the list with an ETag, and create, update and delete.
    # The query is validated with Elasticsearch before it is stored.
    class SavedSearchesController < ApiController
      def index
        data = @user.saved_searches.order(Arel.sql("lower(name)")).map { SavedSearchSerializer.new(_1).to_h }
        return if not_modified?(etag_for("saved_searches", digest(data)))
        render_list(data)
      end

      def create
        record = @user.saved_searches.new(attributes(request.request_parameters, required: true))
        save(record, status: :created)
      end

      def update
        record = @user.saved_searches.find(params[:id])
        record.assign_attributes(attributes(request.request_parameters, required: false))
        save(record, status: :ok)
      end

      def destroy
        @user.saved_searches.find(params[:id]).destroy
        head :no_content
      end

      private

      def attributes(body, required:)
        attributes = {}
        %w[title query].each do |field|
          next unless body.key?(field) || required
          value = body[field]
          raise Problems::InvalidParameter.new("#{field} is required.", pointer: "/#{field}", code: "missing") unless value.is_a?(String) && value.strip.present?
          attributes[(field == "title") ? :name : :query] = value.strip
        end
        attributes
      end

      def save(record, status:)
        if record.save
          render json: SavedSearchSerializer.new(record).to_h, status: status
        elsif record.errors[:query].any?
          render_problem :unprocessable_content, "query_invalid", title: "Query invalid", detail: "The query could not be parsed."
        else
          status_validation_failed(record.errors.map { |error| {pointer: "/#{(error.attribute == :name) ? "title" : error.attribute}", code: "invalid_value", detail: error.full_message} })
        end
      end
    end
  end
end
