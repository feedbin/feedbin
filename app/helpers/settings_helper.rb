module SettingsHelper
  def timeago(time)
    if time.nil?
      "N/A"
    else
      content_tag(:time, time.to_s(:feed), datetime: time.utc.iso8601, class: "timeago", title: "Last updated: #{time.to_s(:feed)}") + " ago"
    end
  end

  def get_tag_names(tags, feed_id)
    if names = tags[feed_id]
      names.join(", ")
    end
  end

  def tag_options
    tags = @user.feed_tags.map { |tag|
      [tag.name, tag.name]
    }
    tags.unshift ["None", ""]
  end

  def plan_name
    if @user.plan.stripe_id == "timed"
      "prepaid plan"
    else
      "trial"
    end
  end

  def bookmarklet
    script = <<~EOD
    (function() {
        var script = document.createElement("script");
        var body = document.querySelector("body");
        var title = document.title;
        document.title = "Sending to Feedbin: " + title;
        script.type = "text/javascript";
        script.async = true;
        script.src = "#{bookmarklet_url(cache_buster: 'replace_me')}".replace("replace_me", Date.now());
        script.setAttribute("data-feedbin-token", "#{@user.page_token}");
        script.setAttribute("data-original-title", title);
        script.onerror = function() {
           window.location = "#{pages_url}?url=" + encodeURIComponent(window.location.href) + "&title=" + encodeURIComponent(title) + "&page_token=#{@user.page_token}";
           document.title = title;
        };
        body.appendChild(script);
    })();
    EOD
    script = script.gsub("\n", "").gsub('"', "%22").gsub(" ", "%20")
    link_to "Send to Feedbin", "javascript:void%20#{script}"
  end
end
