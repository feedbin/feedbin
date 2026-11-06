module Api
  module V3
    class PlaylistWrite
      include BodyFields

      SORTS = PlaylistSerializer::SORTS.invert.freeze
      FIELDS = {"title" => :title, "sort" => :sort_order}.freeze

      attr_reader :body

      def initialize(user, body)
        @user = user
        @body = body
      end

      # An existing title returns that playlist, so a device that created it offline
      # can claim it. => [playlist, created]
      def create
        title = required_string("title")
        sort = body.key?("sort") ? sort_order : "custom"
        playlist = @user.playlists.find_by(title: title) || @user.playlists.create_with(sort_order: sort).create_or_find_by!(title: title)
        [playlist, playlist.previously_new_record?]
      end

      def update(playlist)
        attributes = FIELDS.each_with_object({}) do |(field, column), changed|
          next unless body.key?(field)
          value = (field == "title") ? required_string("title") : sort_order
          # Client stamps carry whole seconds; compare at that precision.
          changed[column] = value unless updated_at(field) < playlist.public_send("#{column}_updated_at").floor
        end
        raise taken if attributes.key?(:title) && @user.playlists.where.not(id: playlist.id).exists?(title: attributes[:title])
        playlist.update!(attributes) if attributes.any?
      rescue ActiveRecord::RecordNotUnique
        # Another request took the title between the check and the write.
        raise taken
      end

      private

      def sort_order
        one_of("sort", SORTS)
      end

      def taken
        invalid("title", "taken", "A playlist with that title already exists.")
      end
    end
  end
end
