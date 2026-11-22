module Api
  module V3
    module ShareServices
      # Sends an article to a service the user has set up: what the service's form takes, as the web's share sheet
      # does. Services that share by link (`sharing: link`) are opened by the app instead.
      class SharesController < ApiController
        include BodyFields
        include ShareServiceScoped

        before_action :set_share_service, :ensure_sends, :ensure_set_up

        def create
          entry = readable_entry
          # The entry's link goes where the web's form puts it (Pinboard's url); the services read it from there.
          result = @record.share(share_params.merge("entry_id" => entry.id, "url" => entry.fully_qualified_url).with_indifferent_access)
          render_result(result, entry)
        end

        private

        def ensure_sends
          return unless ShareServiceCatalog.sharing(@info) == "link"
          raise Problems::InvalidParameter.new("#{@info.label} shares by link: open its share_url.", pointer: "", code: "invalid_value")
        end

        def ensure_set_up
          return if @record&.ok?
          render_problem :unprocessable_content, "needs_setup", title: "Needs setup", detail: "#{@info.label} needs to be set up again."
        end

        def readable_entry
          id = body["entry_id"]
          raise invalid("entry_id", "invalid_value", "entry_id must be an id.") unless id.is_a?(Integer)
          raise ActiveRecord::RecordNotFound unless @user.can_read_entry?(id)
          Entry.find(id)
        end

        # The service's own fields, as its web form sends them: a switch is the form's word for on or off.
        def share_params
          fields = ShareServiceCatalog::SHARE_FIELDS.fetch(@info.service_id, {})
          strings = Array(fields[:strings]).select { body.key?(_1) }.to_h { [_1, optional_string(_1).to_s] }
          switches = (fields[:booleans] || {}).select { |name, _| body.key?(name) }.to_h do |name, (on, off)|
            [name, boolean(name) ? on : off]
          end
          strings.merge(switches)
        end

        def render_result(result, entry)
          error = result[:error]
          if error == "Share limit exceeded"
            status_rate_limited(retry_after: 1.hour, detail: "Too many shares to #{@info.label}. Try again in an hour.")
          elsif result[:url]
            render_problem :unprocessable_content, "needs_setup", title: "Needs setup", detail: error || result[:message]
          elsif error == "This article has no link to share."
            render_problem :unprocessable_content, "no_link", title: "No link", detail: error
          elsif error
            render_problem :unprocessable_content, "share_failed", title: "Share failed", detail: error
          else
            render json: {object: "share", service_id: @info.service_id, entry_id: entry.id}, status: :created
          end
        end
      end
    end
  end
end
