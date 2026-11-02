module Api
  module V3
    # Airshow playlists: the list with an ETag, create (find by title),
    # update and delete. title and sort are edited offline, so each carries
    # {field}_updated_at and the newer value wins; a tie is accepted.
    class PlaylistsController < ApiController
      SORTS = PlaylistSerializer::SORTS.invert.freeze

      def index
        @user.migrate_playlists!
        return if not_modified?(list_etag("playlists"))
        render_list(@user.playlists.order(Arel.sql("lower(title)"), :id).map { PlaylistSerializer.new(_1).to_h })
      end

      # A title the user already has returns that playlist, as Airshow v1
      # does, so a device that created it offline can claim it.
      def create
        body = request.request_parameters
        title = title(body)
        sort_order = body.key?("sort") ? sort_order(body) : "custom"
        playlist = @user.playlists.find_by(title: title) || @user.playlists.create_with(sort_order: sort_order).create_or_find_by!(title: title)
        render json: PlaylistSerializer.new(playlist).to_h, status: playlist.previously_new_record? ? :created : :ok
      end

      def update
        playlist = @user.playlists.find(params[:id])
        body = request.request_parameters
        attributes = {}
        {"title" => :title, "sort" => :sort_order}.each do |field, column|
          next unless body.key?(field)
          value = (field == "title") ? title(body) : sort_order(body)
          # Client stamps carry whole seconds; compare at that precision so a
          # same-second write is a tie.
          attributes[column] = value unless updated_at(body, "#{field}_updated_at") < playlist.public_send("#{column}_updated_at").floor
        end
        if attributes.key?(:title) && @user.playlists.where.not(id: playlist.id).exists?(title: attributes[:title])
          raise invalid("title", "taken", "A playlist with that title already exists.")
        end
        playlist.update!(attributes) if attributes.any?
        render json: PlaylistSerializer.new(playlist).to_h
      end

      # Queue rows and podcast subscriptions in it lose their playlist_id.
      def destroy
        @user.playlists.find(params[:id]).destroy
        head :no_content
      end

      private

      def title(body)
        title = body["title"]
        raise invalid("title", "missing", "title is required.") unless title.is_a?(String) && title.strip.present?
        title.strip
      end

      def sort_order(body)
        SORTS.fetch(body["sort"]) { raise invalid("sort", "invalid_value", "sort must be one of #{SORTS.keys.join(", ")}.") }
      end

      def updated_at(body, field)
        stamp = body[field] or raise invalid(field, "missing", "#{field} is required with #{field.delete_suffix("_updated_at")}.")
        Params.time(stamp) or raise invalid(field, "invalid_value", "#{field} must be an RFC 3339 timestamp with a UTC offset.")
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "/#{field}", code: code)
      end
    end
  end
end
