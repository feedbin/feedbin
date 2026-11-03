module Api
  module V3
    # Actions: the list with an ETag, create, update and delete, and a
    # preview of what the rule matches now. A mute always marks read, so its
    # actions are set here rather than taken from the body. The notifier
    # belonged to the retired Feedbin Notifier: v3 neither shows nor accepts
    # one.
    class ActionsController < ApiController
      include SearchPage

      KINDS = %w[standard mute].freeze
      ACTIONS = %w[mark_read star send_push_notification].freeze
      FIXED_ACTIONS = {"mute" => ["mark_read"]}.freeze

      def index
        data = actions.order(Arel.sql("lower(title)"), :id).map { ActionSerializer.new(_1).to_h }
        return if not_modified?(etag_for("actions", digest(data)))
        render_list(data)
      end

      def create
        action = @user.actions.new
        assign(action, request.request_parameters, required: true)
        save(action, status: :created)
      end

      def update
        action = actions.find(params[:id])
        assign(action, request.request_parameters, required: false)
        save(action, status: :ok)
      end

      def destroy
        actions.find(params[:id]).destroy
        head :no_content
      end

      # The rule's stored scope, so the preview matches what the percolator
      # runs. A scope that lost every feed matches nothing.
      def entries
        action = actions.find(params[:id])
        render_search_page(EntrySearch.new(@user, query: action.query.to_s, feed_ids: action.computed_feed_ids))
      end

      private

      # NULL is an old row from before the column had a default: standard.
      def actions
        @user.actions.where(action_type: [nil, *KINDS])
      end

      def assign(action, body, required:)
        if body.key?("title") || required
          title = body["title"]
          raise invalid("title", "missing", "title is required.") unless title.is_a?(String) && title.strip.present?
          action.title = title.strip
        end

        if body.key?("kind") || required
          raise invalid("kind", "invalid_value", "kind must be one of #{KINDS.join(", ")}.") unless KINDS.include?(body["kind"])
          action.action_type = body["kind"]
        end

        if body.key?("query")
          query = body["query"]
          raise invalid("query", "invalid_value", "query must be a string.") unless query.nil? || query.is_a?(String)
          action.query = query&.strip
        end

        assign_scope(action, body, required: required)

        if body.key?("actions")
          values = body["actions"]
          raise invalid("actions", "invalid_value", "actions must be an array of #{ACTIONS.join(", ")}.") unless values.is_a?(Array) && values.all? { ACTIONS.include?(_1) }
          action.actions = values.uniq
        end
        action.actions = FIXED_ACTIONS[action.action_type] if FIXED_ACTIONS.key?(action.action_type)
      end

      # Both lists empty as sent means every feed. Ids the user cannot use are
      # dropped afterwards, so a list of only foreign ids fails validation
      # instead of widening the rule to every feed.
      def assign_scope(action, body, required:)
        return unless required || body.key?("feed_ids") || body.key?("tag_ids")
        current = {"feed_ids" => action.all_feeds ? [] : action.feed_ids.reject(&:blank?).map(&:to_i), "tag_ids" => action.all_feeds ? [] : action.tag_ids}
        sent = current.to_h do |field, stored|
          next [field, stored] unless body.key?(field)
          ids = body[field]
          raise invalid(field, "invalid_value", "#{field} must be an array of ids.") unless ids.is_a?(Array) && ids.all? { _1.is_a?(Integer) }
          [field, ids.uniq]
        end
        action.all_feeds = sent.values.all?(&:empty?)
        action.feed_ids = sent["feed_ids"] & @user.subscriptions.pluck(:feed_id)
        action.tag_ids = sent["tag_ids"] & @user.taggings.distinct.pluck(:tag_id)
      end

      def save(action, status:)
        if action.save
          render json: ActionSerializer.new(action).to_h, status: status
        elsif action.errors.added?(:base, "Search syntax invalid")
          render_problem :unprocessable_content, "query_invalid", title: "Query invalid", detail: "The query could not be parsed."
        else
          # The one other base error is a scope with no feeds left in it.
          status_validation_failed(action.errors.map { |error|
            {pointer: (error.attribute == :base) ? "/feed_ids" : "/#{error.attribute}", code: (error.type == :blank) ? "missing" : "invalid_value", detail: error.full_message}
          })
        end
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "/#{field}", code: code)
      end
    end
  end
end
