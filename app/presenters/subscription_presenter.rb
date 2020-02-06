class SubscriptionPresenter < BasePresenter
  presents :subscription

  def graph_volume
    @template.number_with_delimiter(total_posts)
  end

  def total_posts
    counts.sum
  end

  def graph_date_start
    days.ago.to_s(:day_month).upcase
  end

  def graph_date_mid
    total_days = (Time.now - days.ago).to_i
    (days.ago + total_days / 2).to_s(:day_month).upcase
  end

  def graph_date_end
    Time.now.to_s(:day_month).upcase
  end

  def graph_bars
    max = counts.max
    counts.each_with_index.map do |count, index|
      percent = (count == 0) ? 0 : ((count.to_f / max.to_f) * 100).round
      date = (days.ago + index.days)
      ordinal = date.day.ordinalize
      display_date = "#{date.strftime("%B")} #{ordinal}"
      OpenStruct.new(percent: percent, count: count, day: display_date)
    end
  end

  def graph_quarter(quarter)
    count = counts.max.to_f / 4.to_f
    if count == 0 || (quarter != 4 && counts.max < 4)
      nil
    else
      (count * quarter).round
    end
  end

  def bar_class(data)
    data.count == 0 ? "zero" : ""
  end

  def bar_title(data)
    type = (subscription.feed.twitter_feed?) ? "tweet" : "article"
    "#{data.day}: #{data.count} #{type.pluralize(data.count)}"
  end

  def muted_status
    if subscription.muted
      "muted"
    end
  end

  def mute_class
    if subscription.muted
      "status-muted"
    end
  end

  def sparkline
    Sparkline.new(width: 80, height: 15, stroke: 2, percentages: subscription.entries_count)
  end

  private

  def counts
    @counts ||= FeedStat.get_entry_counts([subscription.feed.id], days.ago).values.first
  end

  def days
    29.days
  end
end
