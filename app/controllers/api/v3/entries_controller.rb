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

      # POST /entries/state: the verbs, from the raw body so a verb's array
      # arrives as JSON gave it rather than filtered through params.
      def state
        render json: StateChange.new(@user, request.request_parameters).call
      end

      private

      # Not paginated. Ids that don't exist or the user can't read come back
      # in meta.missing, so a client can drop them from its cache.
      def render_ids
        ids = requested_ids
        readable = @user.can_read_filter(ids)
        entries = Entry.where(id: readable).merge(with_associations).index_by(&:id)
        render_list(
          serialize(ids.filter_map { entries[_1] }),
          meta: {as_of: as_of, missing: ids - entries.keys}
        )
      end

      def requested_ids
        ids = params[:ids].to_s.split(",").map { Integer(_1.strip, exception: false) }
        if ids.empty? || ids.any? { _1.nil? || _1 <= 0 }
          raise Problems::InvalidParameter.new("ids must be comma-separated entry ids.", pointer: "ids", code: "invalid_value")
        end
        if ids.size > MAX_IDS
          raise Problems::InvalidParameter.new("ids takes at most #{MAX_IDS} ids.", pointer: "ids", code: "too_many")
        end
        ids.uniq
      end

    end
  end
end
