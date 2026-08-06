module SettingsHelper
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
end
