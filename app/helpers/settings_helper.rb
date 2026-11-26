module SettingsHelper
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
          script.src = "#{bookmarklet_url(cache_buster: "replace_me")}".replace("replace_me", Date.now());
          script.setAttribute("data-feedbin-token", "#{@user.page_token}");
          script.setAttribute("data-original-title", title);
          script.onerror = function() {
             document.title = title;
             var form = document.createElement("form");
             form.method = "POST";
             form.action = "#{pages_url}";
             var values = {url: window.location.href, title: title, page_token: "#{@user.page_token}"};
             Object.keys(values).forEach(function(name) {
                 var input = document.createElement("input");
                 input.type = "hidden";
                 input.name = name;
                 input.value = values[name];
                 form.appendChild(input);
             });
             body.appendChild(form);
             form.submit();
          };
          body.appendChild(script);
      })();
    EOD
    script = script.delete("\n").gsub('"', "%22").gsub(" ", "%20")
    "javascript:void%20#{script}"
  end

  # A store subscription in a line, as the app's Billing page has it:
  # "$7.00 a month · Renews December 25, 2026".
  def store_subscription_summary(subscription)
    parts = []
    if subscription.price
      price = (subscription.currency == "USD") ? number_to_currency(subscription.price) : "#{format("%.2f", subscription.price)} #{subscription.currency}"
      parts << "#{price} a #{(subscription.period == "yearly") ? "year" : "month"}"
    end
    if subscription.grace? || subscription.retrying?
      parts << "Payment failed"
    elsif subscription.expires_at
      parts << "#{subscription.renews? ? "Renews" : "Ends"} #{subscription.expires_at.to_date.strftime("%B %-d, %Y")}"
    end
    parts.join(" · ")
  end

  # Where a store subscription is managed: "the App Store" or "Google Play".
  def store_name(subscription)
    subscription.google? ? "Google Play" : "the App Store"
  end
end
