class SubscriptionPresenter < BasePresenter

  presents :subscription

  def graph_volume
    @template.number_with_delimiter(counts.sum)
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
    counts.map { |count| (count.to_f / max.to_f) }.to_json
  end

  def graph_max
    max = counts.max
    if max == 0
      nil
    else
      max
    end
  end

  def graph_mid
    mid = counts.max / 2
    if mid == 0
      nil
    else
      mid
    end
  end

  private

  def counts
    @counts ||= FeedStat.get_entry_counts([subscription.feed.id], days.ago).values.first
  end

  def days
    29.days
  end

end