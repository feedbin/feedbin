module Api
  module V3
    # A supported share service with the user's setup of it, if any.
    class ShareServiceSerializer
      def initialize(info, record)
        @info = info
        @record = record
      end

      def to_h
        {
          object: "share_service",
          id: @info.service_id,
          label: @info.label,
          setup: ShareServiceCatalog.setup(@info),
          sharing: ShareServiceCatalog.sharing(@info),
          status: status,
          share_url: ShareServiceCatalog::LINKS[@info.service_id],
          settings: settings,
          choices: choices,
          default_choice: @record&.default_option.presence
        }
      end

      private

      def status
        return "inactive" unless @record
        @record.auth_error? ? "auth_error" : "active"
      end

      # What the user filled in setting it up; nothing secret. Each is null unless the service has it.
      def settings
        {
          email_name: (@record&.email_name if @info.service_id == "email"),
          email_address: (@record&.email_address if @info.service_id == "email"),
          kindle_address: (@record&.kindle_address if @info.service_id == "kindle"),
          mastodon_host: (@record&.mastodon_host if @info.service_id == "mastodon")
        }
      end

      # Where a share can go: a Tumblr blog, an Evernote notebook.
      def choices
        options = @record&.service_options
        case options
        when Array then options.map { {value: _1.to_s, label: _1.to_s} }
        when Hash then options.except("completions").map { |label, value| {value: value.to_s, label: label.to_s} }
        else []
        end
      end
    end
  end
end
