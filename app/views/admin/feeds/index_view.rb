module Admin
  module Feeds
    class IndexView < ApplicationView

      def initialize(params:, feed:)
        @params = params
        @feed = feed
      end

      def view_template
        render Settings::H1Component.new do
          "Feed Admin"
        end

        form_tag(admin_feeds_path, method: "get", class: "mb-4") do
          render Form::TextInputComponent.new do |input|
            input.input do
              input(
                type: "search",
                class: "feed-search peer text-input",
                placeholder: "Find Feed by URL or ID",
                name: "q",
                value: @params[:q]
              )
            end
            input.accessory_leading do
              Icon("icon-search", class: "ml-2 fill-400 pg-focus:fill-blue-600")
            end
          end
        end


        if !@feed.nil? && @feed.blank?
          not_found
        elsif @feed && feed = @feed.first
          render FeedView.new(feed: feed)
        end

      end

      def not_found
        render "shared/error_message" do
          plain "No matches."
        end
      end
    end


    class FeedView < ApplicationView
      def initialize(feed:)
        @feed = feed
      end

      def view_template
        div class: "p-4 grow border rounded-lg mb-8" do

          div class: "flex items-center mb-8" do
            div class: "grow" do
              render App::FeedComponent do |feed|
                feed.icon do
                  favicon_with_record(@feed.favicon, host: @feed.host, generated: true)
                end
                feed.title do
                  link_to(@feed.site_url, target: :blank, class: "!text-600") do
                    @feed.title
                  end
                end
                feed.subhead do
                  link_to(@feed.feed_url, class: "!text-500 truncate", target: :blank) do
                    short_url_alt(@feed.feed_url)
                  end
                end
              end
            end


            if @feed.fixable?
              Icon("menu-icon-fix-feeds", class: "fill-600", title: "Fixable feed", data: {toggle: "tooltip"})
            elsif @feed.dead?
              Icon("menu-icon-skull", class: "fill-600", title: "#{@feed.crawl_data.error_count} #{"Error".pluralize(@feed.crawl_data.error_count)}", data: {toggle: "tooltip"})
            elsif @feed.crawl_data.error_count > 0
              Icon("icon-error-message-small", title: "#{@feed.crawl_data.error_count} #{"Error".pluralize(@feed.crawl_data.error_count)}", data: {toggle: "tooltip"})
            else
              sparkline
            end


          end

          render Settings::ControlGroupComponent.new do |group|
            group.header { plain " Stats " }

            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { "Last Crawled" }

                row.control do
                  span(class: "text-500") do
                    last_crawled
                  end
                end
              end
            end
          end

        end
      end

      def sparkline
        counts = FeedStat.daily_counts(feed_ids: [@feed.id], interval: 89.days.inspect).values.first.counts
        if counts.present?
          max = counts.max.to_i
          counts = counts.map do |count|
            if count == 0
              0.to_f
            else
              count.to_f / max.to_f
            end
          end
        end

        Sparkline(sparkline: ::Sparkline.new(width: 80, height: 15, stroke: 1, percentages: counts), theme: true)
      end

      def last_crawled
        @feed.crawl_data.downloaded_at == 0 ? "Never" : Time.at(@feed.crawl_data.downloaded_at).utc.to_formatted_s(:datetime)
      end

    end
  end
end