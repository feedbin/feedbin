module Api
  module V3
    # GET /entries: the timeline, the entries whose content changed, or a
    # set of entries by id. There is no GET /entries/{id}; ids= covers it.
    class EntriesController < ApiController
      include Timeline

      MAX_IDS = 500

      def index
        params.key?(:ids) ? render_ids : render_timeline
      end

      private

      # Not paginated. Ids that don't exist or the user can't read come back
      # in meta.missing, so a client can drop them from its cache.
      def render_ids
        ids = id_list(:ids, max: MAX_IDS, of: "entry ids")
        entries = Entry.where(id: @user.can_read_filter(ids)).for_api_v3.index_by(&:id)
        render_list(
          serialize_entries(ids.filter_map { entries[_1] }),
          meta: {as_of: as_of, missing: ids - entries.keys}
        )
      end
    end
  end
end
