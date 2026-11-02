module Api
  module V3
    # GET /collections/{id}/ids: the whole id list of one collection, in one
    # response, with an ETag. Only unread and starred exist so far; the other
    # collections in the spec are 404 until they ship.
    class CollectionsController < ApiController
      COLLECTIONS = {
        "unread" => :unread_entries,
        "starred" => :starred_entries
      }.freeze

      def ids
        association = COLLECTIONS[params[:id]] or return status_not_found
        return if not_modified?(list_etag(params[:id]))

        # starred_entries.entry_id is nullable; an id list holds integers only.
        render_list(@user.public_send(association).where.not(entry_id: nil).order(:entry_id).pluck(:entry_id))
      end
    end
  end
end
