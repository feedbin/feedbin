module Settings
  module Subscriptions
    module Shared
      class FormComponent < ApplicationComponent
        attr_reader :subscription

        def initialize(subscription:, tag_editor:)
          @subscription = subscription
          @tag_editor = tag_editor
        end

        def view_template
          view_context.present subscription do |subscription_presenter|
            feed_profile(subscription_presenter)
            chart(subscription_presenter)
            settings(subscription_presenter)
          end
        end

        def feed_profile(subscription_presenter)
          div(class: "border rounded-lg mb-14") do
            div(class: "flex items-center gap-2 p-4") do
              raw subscription_presenter.favicon(subscription.feed)
              span(data_behavior: "user_title", class: "truncate text-lg mr-6") do
                subscription.title
              end
              link_to "Edit", edit_subscription_path(subscription.feed), remote: true, class: "button button-secondary !ml-auto", data: { open_dialog: Dialog::EditSubscription.dom_id }
            end
            if subscription.feed.twitter_feed?
              twitter_notice
            elsif subscription.feed.crawl_error?
              error_notice
            end
          end
        end

        def twitter_notice
          div(class: "border-t flex gap-2 p-4") do
            div(class: "pt-1 shrink-0 flex flex-center w-[20px] h-[20px]") do
              Icon("menu-icon-skull", class: "fill-600")
            end
            div do
              p(class: "text-red-600") { "Twitter Not Supported" }
              p(class: "text-500 text-sm") do
                plain "Feedbin "
                a( href: "https://feedbin.com/blog/2023/03/30/twitter-access-revoked/" ) { "no longer has access" }
                plain " to the Twitter API."
              end
            end
          end
        end

        def error_notice
          div(class: "border-t p-4", id: dom_id(@subscription, :fixable)) do
            div(class: "flex gap-2") do
              div(class: "pt-1 shrink-0 flex flex-center w-[20px] h-[20px]") do
                if @subscription.feed.discovered_feeds.present?
                  Icon("menu-icon-fix-feeds", class: "fill-600 mt-0.5")
                else
                  Icon("menu-icon-skull", class: "fill-600")
                end
              end
              div(class: "grow") do
                p(class: "flex gap-2 items-baseline") do
                  span class: "block grow" do
                    span(title: @subscription.feed.crawl_error_message, data: {toggle: "tooltip"}) do
                      if @subscription.feed.discovered_feeds.present?
                        "Fixable Feed"
                      else
                        span(class: "text-red-600") do
                          "Crawl Error"
                        end
                      end
                    end
                  end

                  if !@subscription.feed.discovered_feeds.present? && @subscription.feed.last_published_entry.respond_to?(:to_formatted_s)
                    span(class: "text-500 text-sm") do
                      plain "Last worked: "
                      plain @subscription.feed.last_published_entry&.to_formatted_s(:month_year)
                    end
                  end
                end
                p(class: "text-500 text-sm") do
                  plain "Feedbin is unable to download this feed."
                  if @subscription.feed.discovered_feeds.present?
                    plain " However, it looks like there may be a working alternative available."
                  end
                end

                if @subscription.feed.discovered_feeds.present?
                  render FixFeeds::SuggestionComponent.new(replaceable: @subscription, source: @subscription.feed, redirect: edit_settings_subscription_url(@subscription), remote: false)
                end
              end
            end
          end
        end

        def chart(subscription_presenter)
          div(class: "chart-wrap leading-none flex mb-8 pb-[21px]") do
            div(class: "flex grow pt-[20%] border-b mr-[5px] relative") do
              div(class: "flex shrink-0 flex-col justify-between text-right absolute top-0 left-0 right-0 bottom-[2px]" ) do
                div(class: "w-full border-t border-200 border-dashed")
                div(class: "w-full border-t border-200 border-dashed")
                div(class: "w-full border-t border-200 border-dashed")
                div(class: "w-full border-t border-200 border-dashed")
                div(class: "w-full border-t border-200 border-dashed invisible")
              end
              div(class: "flex items-stretch flex-nowrap absolute top-0 left-0 right-0 bottom-[2px]", data_behavior: "hide_tooltip tooltip_controller" ) do
                div(class: "absolute top-[10px] left-[10px] bg-100 border p-1 leading-none text-[10px] rounded whitespace-nowrap transition group opacity-0 data-[visible=true]:opacity-100", data_visible: "false", data_behavior: "tooltip_target", data_position: "left" ) do
                  div(class: "w-0 h-0 border-x-transparent border-l-[4px] border-t-[4px] border-r-[4px] block absolute bottom-[-4px] group-data-[position=left]:left-[13px] group-data-[position=right]:right-[9px]" )
                  div(class: "w-0 h-0 border-x-transparent border-l-[3px] border-t-[3px] border-r-[3px] block absolute bottom-[-3px] group-data-[position=left]:left-[14px] group-data-[position=right]:right-[10px] border-100" )
                  div(class: "uppercase text-500 mb-1", data_behavior: "tooltip_day" )
                  div(class: "text-600 font-bold", data_behavior: "tooltip_count")
                end
                subscription_presenter.graph_bars.each do |data|
                  div( class: "bar-sleeve flex-nowrap flex items-end grow first:m-0", data_day: data.day, data_count: subscription_presenter.bar_count(data), data_behavior: "show_tooltip" ) do
                    div(style: %(height: #{data.percent}%;), class: %(ml-[2px] min-h-[1px] content-[''] grow bg-green-600 #{data.count == 0 ? "rounded-t-none" : "rounded-t"}))
                  end
                end
              end
              div( class: "absolute inset-x-0 bottom-[-18px] justify-between flex text-400 text-xs leading-none" ) do
                div { subscription_presenter.graph_date_start }
                div { subscription_presenter.graph_date_mid }
                div { subscription_presenter.graph_date_end }
              end
            end
            div( class: "flex shrink-0 flex-col justify-between text-right text-400 text-xs leading-none" ) do
              div(class: "relative top-[-5px]") do
                subscription_presenter.graph_quarter(4)
              end
              div(class: "relative top-[-3px]") do
                subscription_presenter.graph_quarter(3)
              end
              div(class: "relative top-[-1px]") do
                subscription_presenter.graph_quarter(2)
              end
              div(class: "relative top-[1px]") do
                subscription_presenter.graph_quarter(1)
              end
              div(class: "relative top-[3px]") { "0" }
            end
          end
        end

        def settings(subscription_presenter)
          form_with model: subscription, url: settings_subscription_path, data: { remote: true } do |form|

            render Settings::ControlGroupComponent.new class: "mb-14" do |group|
              group.header { plain " Stats " }

              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Subscribed" }

                  row.control do
                    span(class: "text-500") do
                      subscription.created_at.to_formatted_s(:date)
                    end
                  end
                end
              end

              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title do
                    plain " Latest "
                    if subscription.feed.twitter_feed?
                      plain " Tweet "
                    else
                      plain " Article "
                    end
                  end

                  row.control do
                    span(class: "text-500") do
                      plain subscription.feed.try(:last_published_entry).try(:to_formatted_s, :date) || "N/A"
                    end
                  end
                end
              end

              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Volume" }

                  row.control do
                    span(class: "text-500") do
                      plain subscription_presenter.graph_volume
                      if subscription.feed.twitter_feed?
                        plain " tweet".pluralize(subscription_presenter.graph_volume)
                        plain " / month "
                      else
                        plain " article".pluralize(subscription_presenter.total_posts)
                        plain " / month "
                      end
                    end
                  end
                end
              end

              unless subscription.feed.twitter_feed?
                group.item do
                  render Settings::ControlRowComponent.new do |row|
                    row.title { "Website" }

                    row.control do
                      a(href: subscription.feed.site_url, class: "!text-500 truncate" ) { short_url(subscription.feed.site_url) }
                    end
                  end
                end
              end

              group.item do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Source" }

                  row.control do
                    a( href: subscription.feed.feed_url, class: "!text-500 truncate" ) { short_url(subscription.feed.feed_url) }
                  end
                end
              end
            end

            render Settings::ControlGroupComponent.new class: "mb-14" do |group|
              group.header { "Options" }

              group.item do
                form.check_box :muted, class: "peer", data: { behavior: "auto_submit" }, id: "subscription_muted"
                form.label :muted, class: "group" do
                  render Settings::ControlRowComponent.new do |row|
                    row.title { "Muted" }
                    row.control { render Form::SwitchComponent.new }
                  end
                end
              end

              group.item do
                form.check_box :show_updates, class: "peer", data: { behavior: "auto_submit" }, id: "subscription_show_updates"
                form.label :show_updates, class: "group" do
                  render Settings::ControlRowComponent.new do |row|
                    row.title { "Show Updates" }

                    row.description do
                      "Tells you when an article has been changed after being published"
                    end

                    row.control { render Form::SwitchComponent.new }
                  end
                end
              end

              if subscription.feed.twitter_feed?
                group.item do
                  form.check_box :show_retweets, class: "peer", data: { behavior: "auto_submit" }, id: "subscription_show_retweets"

                  form.label :show_retweets, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Show Retweets" }
                      row.control { render Form::SwitchComponent.new }
                    end
                  end
                end

                group.item do
                  form.check_box :media_only, class: "peer", data: { behavior: "auto_submit" }, id: "subscription_media_only"
                  form.label :media_only, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Media Only" }

                      row.description do
                        "Only show tweets that contain links or images"
                      end

                      row.control { render Form::SwitchComponent.new }
                    end
                  end
                end
              else
                group.item do
                  render Settings::ControlRowComponent.new do |row|
                    row.title do
                      link_to "Refresh Favicon", refresh_favicon_settings_subscription_path( subscription ), remote: true, method: :post
                    end
                  end
                end
              end
            end
          end
        end

      end
    end
  end
end