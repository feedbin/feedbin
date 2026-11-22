module Api
  module V3
    # The share services an app offers, as the web's Share & Save page does: each supported one that is still
    # offered, with how it is set up and how it shares.
    class ShareServiceCatalog
      # How a service is set up.
      SETUP = {
        "email" => "email", "kindle" => "kindle", "pinboard" => "token", "xauth" => "token",
        "oauth" => "oauth", "oauth2" => "oauth", "popover" => "none"
      }.freeze

      # What sharing to it sends: the fields a share takes, by kind.
      SHARE_FIELDS = {
        "email" => {strings: %w[to subject body], booleans: {"readability" => %w[on off]}},
        "pinboard" => {strings: %w[description extended tags], booleans: {"shared" => %w[yes no], "toread" => %w[yes no]}},
        "micro_blog" => {strings: %w[name content]},
        "tumblr" => {strings: %w[title description source tags type format state site]},
        "evernote" => {strings: %w[title tags notebook_guid], booleans: {"readability" => %w[on off]}},
        "mastodon" => {strings: %w[status spoiler_text visibility]},
        "kindle" => {booleans: {"extract" => %w[true false]}}
      }.freeze

      LINKS = {
        "twitter" => "#{Share::Twitter::URL}?url=${url}&text=${title}",
        "facebook" => "#{Share::Facebook::URL}?u=${url}&display=popup",
        "buffer" => "#{Share::Buffer::URL}?url=${url}&text=${title}"
      }.freeze

      def self.offered
        SupportedSharingService::SERVICES.reject { _1[:active] == false }.sort_by(&:service_id)
      end

      def self.info!(service_id)
        offered.find { _1.service_id == service_id } or raise ActiveRecord::RecordNotFound
      end

      def self.setup(info)
        return "server" if info.service_id == "mastodon"
        SETUP.fetch(info.service_type)
      end

      def self.sharing(info)
        return "link" if info.service_type == "popover"
        info.has_share_sheet ? "form" : "send"
      end

      def initialize(user)
        @records = user.supported_sharing_services.index_by(&:service_id)
      end

      def services
        self.class.offered.map { ShareServiceSerializer.new(_1, @records[_1.service_id]).to_h }
      end
    end
  end
end
