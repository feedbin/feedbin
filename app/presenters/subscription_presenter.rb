class SubscriptionPresenter < BasePresenter

  presents :subscription

  def graph_volume
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
    output = ""
    counts.map { |count| (count.to_f / max.to_f) * 100 }.each do |percentage|
      output += @template.content_tag(:div, '', style: "height: #{percentage}%")
    end
    output.html_safe
  end

  def graph_max
    counts.max
  end

  def graph_mid
    counts.max / 2
  end

  private

  def counts
    @counts ||= FeedStat.get_entry_counts([subscription.feed.id], days.ago).values.first
  end

  def days
    29.days
  end

end