module Api
  module V2
    class EntryCountsController < ApiController
      respond_to :json
      skip_before_action :valid_user

      def post_frequency
        @user = current_user
        feed_ids = @user.subscriptions.pluck(:feed_id)
        counts = get_post_frequency(feed_ids)
        render json: counts.to_json
      end

      private

      def get_post_frequency(feed_ids)
        days = params[:days].present? ? params[:days].to_i : 6
        start_date = days.days.ago
        end_date = Time.now

        query = total_activity_query
        query = ActiveRecord::Base.send(:sanitize_sql_array, [query, start_date, end_date, start_date, feed_ids])
        results = ActiveRecord::Base.connection.execute(query)

        results.each_with_object([]) do |result, array|
          array.push(result["entries_count"].to_i)
        end
      end

      def total_activity_query
        <<-eos
          SELECT
            date,
            coalesce(entries_count,0) AS entries_count
          FROM
          generate_series(
            ?::date,
            ?::date,
            '1 day'
          ) AS date
          LEFT OUTER JOIN (
            SELECT
            day,
            sum(entries_count) AS entries_count
            FROM feed_stats
            WHERE day >= ?
            AND feed_id IN (?)
            GROUP BY day
          ) results
          ON (date = results.day)
        eos
      end
    end
  end
end
