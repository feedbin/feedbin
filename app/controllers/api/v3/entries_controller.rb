module Api
  module V3
    class EntriesController < ApiController
      include Timeline

      MAX_IDS = 500

      def index
        params.key?(:ids) ? render_ids : render_timeline
      end

      private

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
