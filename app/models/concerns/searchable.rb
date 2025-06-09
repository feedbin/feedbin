module Searchable
  extend ActiveSupport::Concern

  included do
    UNREAD_REGEX = /(?<=\s|^)(?:(?<boolean>AND|OR|NOT)\s+)?is:\s*unread(?=\s|$)/
    READ_REGEX = /(?<=\s|^)is:\s*read(?=\s|$)/
    STARRED_REGEX = /(?<=\s|^)(?:(?<boolean>AND|OR|NOT)\s+)?is:\s*starred(?=\s|$)/
    UNSTARRED_REGEX = /(?<=\s|^)is:\s*unstarred(?=\s|$)/
    SORT_REGEX = /(?<=\s|^)sort:\s*(asc|desc|relevance)(?=\s|$)/i
    TAG_ID_REGEX = /tag_id:\s*(\d+)/
    TAG_GROUP_REGEX = /tag_id:\((.*?)\)/
    RANGE_REGEX = /published:\(.*?\)|published:\[.*?\]|updated:\(.*?\)|updated:\[.*?\]|media_duration:\(.*?\)|media_duration:\[.*?\]|word_count:\(.*?\)|word_count:\[.*?\]/
    RANGE_UNBOUNDED_REGEX = /published:[<>=+].*?(?=\s|$)|updated:[<>=+].*?(?=\s|$)|media_duration:[<>=+].*?(?=\s|$)|word_count:[<>=+].*?(?=\s|$)/

    def self.saved_search_count(user)
      saved_searches = user.saved_searches
      if saved_searches.length < 50
        unread_entries = user.unread_entries.pluck(:entry_id)
        searches = build_multi_search(user, saved_searches)
        records = searches.map { Search::MultiSearchRecord.new(query: _1.query) }

        if records.present?
          responses = Search.client { _1.msearch(Entry.table_name, records: records) }
          entry_ids = responses.map(&:ids)
          search_ids = searches.map(&:id)
          Hash[search_ids.zip(entry_ids)]
        end
      end
    end

    def self.build_multi_search(user, saved_searches)
      saved_searches.filter_map { |saved_search|
        query_string = saved_search.query

        next if READ_REGEX.match?(query_string)

        query_string = query_string.gsub(UNREAD_REGEX, "")
        query  = build_query(user: user, query: "#{query_string} is:unread", size: 50)
        query = query.slice(:query, :from, :size)
        OpenStruct.new({id: saved_search.id, query: query})
      }
    end

    def self.scoped_search(params, user)
      data     = params.clone
      per_page = data.delete(:per_page) || WillPaginate.per_page
      page     = data.delete(:page) || 1
      query    = build_query(user: user, query: data[:query], feed_ids: data[:feed_ids])

      result = Search.client { _1.validate(Entry.table_name, query: {query: query[:query]}) }
      if result == false
        Search::Response.new({})
      else
        Search.client { _1.search(Entry.table_name, query: query, page: page, per_page: per_page) }
      end
    end

    def self.escape_search(query)
      if query.present? && query.respond_to?(:gsub)
        extracted_fields = []

        query = query.gsub(RANGE_REGEX) { |match|
          extracted_fields.push(match)
          ""
        }

        query = query.gsub(RANGE_UNBOUNDED_REGEX) { |match|
          extracted_fields.push(match)
          ""
        }

        special_characters_regex = /([\+\-\!\{\}\[\]\^\~\?\\\/])/
        escape = '\ '.sub(" ", "")
        query = query.gsub(special_characters_regex) { |character| escape + character }

        query = query.gsub("title_exact:",   "title.exact:")
        query = query.gsub("content_exact:", "content.exact:")
        query = query.gsub("body:",          "content:")
        query = query.gsub("emoji:",         "")
        query = query.gsub("_missing_:",     "NOT _exists_:")

        colon_regex = /(?<!title|title.exact|feed_id|content|content.exact|author|_missing_|_exists_|twitter_screen_name|twitter_name|twitter_retweet|twitter_media|twitter_image|twitter_link|emoji|url|url.exact|link|type|category):(?=.*)/
        query = query.gsub(colon_regex, '\:')

        extracted_fields.push(query).join(" ")
      end
    end

    def self.replace_tag_ids(query, user)
      tag_replacer = proc do |ids|
        ids = [*ids]
        feed_ids = user.taggings.where(tag_id: ids).pluck("DISTINCT feed_id")
        string = feed_ids.join(" OR ")
        if feed_ids.length == 1
          "feed_id:#{string}"
        else
          "feed_id:(#{string})"
        end
      end

      query = query.gsub(TAG_ID_REGEX) {
        tag_id = Regexp.last_match[1]
        tag_replacer.call(tag_id)
      }

      query = query.gsub(TAG_GROUP_REGEX) {
        tag_group = Regexp.last_match[1]
        tag_ids = tag_group.split(" OR ")
        tag_replacer.call(tag_ids)
      }

      query
    end

    def self.build_query(user:, query:, feed_ids: nil, size: nil)
      query ||= ""
      query = replace_tag_ids(query, user)
      query = query.gsub(READ_REGEX,      "NOT is:unread")
      query = query.gsub(UNSTARRED_REGEX, "NOT is:starred")
      min_should =

      starred_ids = user.starred_entries.pluck(:entry_id)
      allowed_feed_ids = user.subscriptions.pluck(:feed_id)
      if feed_ids.present?
        allowed_feed_ids = (feed_ids & allowed_feed_ids)
      end

      sort = if matches = SORT_REGEX.match(query)
        query = query.gsub(SORT_REGEX, "")
        matches[1].downcase
      else
        "desc"
      end

      {}.tap do |request|
        request[:query] = {
          bool: {
            filter: {
              bool: {
                should: [
                  {terms: {feed_id: allowed_feed_ids}},
                  {ids: {values: starred_ids}}
                ]
              }
            },
            should: [],
            must: [],
            must_not: []
          }
        }

        request[:fields] = ["id"]

        if size
          request[:from] = 0
          request[:size] = size
        end

        unless sort == "relevance"
          request[:sort] = [{
            published: sort
          }]
        end

        states = [
          [STARRED_REGEX, -> { starred_ids }],
          [UNREAD_REGEX, -> { user.unread_entries.pluck(:entry_id) }]
        ]

        # handles the case of `is:starred OR is:unread`
        or_found = states.any? do |regex, id_source|
          match = regex.match(query)
          match[:boolean] == "OR" if match
        end

        states.each do |regex, id_source|
          if matches = regex.match(query)
            query = query.gsub(regex, "")
            boolean = { ids: { values: id_source.call } }

            case matches[:boolean]
            when "OR"
              request[:query][:bool][:should].push(boolean)
            when "NOT"
              request[:query][:bool][:must_not].push(boolean)
            else # AND + nil
              target = or_found ? :should : :must
              request[:query][:bool][target].push(boolean)
            end
          end
        end

        query = escape_search(query)
        if query.present?
          request[:query][:bool][:should].push({
            query_string: {
              fields: ["title", "title.*", "content", "content.*", "author", "url", "link"],
              quote_field_suffix: ".exact",
              default_operator: "AND",
              allow_leading_wildcard: false,
              query: query
            }
          })
        end

        if request[:query][:bool][:should].present?
          request[:query][:bool][:minimum_should_match] = 1
        end
      end
    end
  end
end
