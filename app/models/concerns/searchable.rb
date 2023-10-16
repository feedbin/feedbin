module Searchable
  extend ActiveSupport::Concern

  included do
    UNREAD_REGEX = /(?<=\s|^)is:\s*unread(?=\s|$)/
    READ_REGEX = /(?<=\s|^)is:\s*read(?=\s|$)/
    STARRED_REGEX = /(?<=\s|^)is:\s*starred(?=\s|$)/
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
      saved_searches.map { |saved_search|
        query_string = saved_search.query

        next if READ_REGEX.match?(query_string)

        query_string = query_string.gsub(UNREAD_REGEX, "")
        query  = build_query(user: user, query: "#{query_string} is:unread", size: 50)
        query = query.slice(:query, :from, :size)
        OpenStruct.new({id: saved_search.id, query: query})
      }.compact
    end

    def self.scoped_search(params, user)
      data = params.clone
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

        query = query.gsub("title_exact:", "title.exact:")
        query = query.gsub("content_exact:", "content.exact:")
        query = query.gsub("body:", "content:")
        query = query.gsub("emoji:", "")
        query = query.gsub("_missing_:", "NOT _exists_:")

        colon_regex = /(?<!title|title.exact|feed_id|content|content.exact|author|_missing_|_exists_|twitter_screen_name|twitter_name|twitter_retweet|twitter_media|twitter_image|twitter_link|emoji|url|url.exact|link|type):(?=.*)/
        query = query.gsub(colon_regex, '\:')

        extracted_fields.push(query).join(" ")
      end
    end

    def self.build_query(user:, query:, feed_ids: nil, size: nil)
      read             = nil
      starred          = nil
      sort             = nil
      extracted_fields = []

      if UNREAD_REGEX.match?(query)
        query = query.gsub(UNREAD_REGEX, "")
        read = false
      elsif READ_REGEX.match?(query)
        query = query.gsub(READ_REGEX, "")
        read = true
      end

      if STARRED_REGEX.match?(query)
        query = query.gsub(STARRED_REGEX, "")
        starred = true
      elsif UNSTARRED_REGEX.match?(query)
        query = query.gsub(UNSTARRED_REGEX, "")
        starred = false
      end

      if SORT_REGEX.match?(query)
        sort = query.match(SORT_REGEX)[1].downcase
        query = query.gsub(SORT_REGEX, "")
      end

      if query
        query = query.gsub(TAG_ID_REGEX) { |s|
          tag_id = Regexp.last_match[1]
          feed_ids = user.taggings.where(tag_id: tag_id).pluck(:feed_id)
          id_string = feed_ids.join(" OR ")
          "feed_id:(#{id_string})"
        }

        query = query.gsub(TAG_GROUP_REGEX) { |s|
          tag_group = Regexp.last_match[1]
          tag_ids = tag_group.split(" OR ")
          feed_ids = user.taggings.where(tag_id: tag_ids).pluck(:feed_id).uniq
          id_string = feed_ids.join(" OR ")
          "feed_id:(#{id_string})"
        }

      end

      query = escape_search(query)

      options = {
        query: query,
        sort: "desc",
        starred_ids: [],
        ids: [],
        not_ids: [],
        feed_ids: []
      }

      if sort && %w[desc asc relevance].include?(sort)
        options[:sort] = sort
      end

      if read == false
        ids = [0]
        ids.concat(user.unread_entries.pluck(:entry_id))
        options[:ids].push(ids)
      elsif read == true
        options[:not_ids].push(user.unread_entries.pluck(:entry_id))
      end

      if starred == true
        ids = [0]
        ids.concat(user.starred_entries.pluck(:entry_id))
        options[:ids].push(ids)
      elsif starred == false
        options[:not_ids].push(user.starred_entries.pluck(:entry_id))
      end

      subscribed_ids = user.subscriptions.pluck(:feed_id)
      if feed_ids.present?
        options[:feed_ids] = (feed_ids & subscribed_ids)
      else
        options[:feed_ids] = subscribed_ids
        options[:starred_ids] = user.starred_entries.pluck(:entry_id)
      end

      if options[:ids].present?
        options[:ids] = options[:ids].inject(:&)
      end

      if options[:not_ids].present?
        options[:not_ids] = options[:not_ids].flatten.uniq
      end

      {}.tap do |hash|
        hash[:fields] = ["id"]
        if options[:sort]
          if %w[desc asc].include?(options[:sort])
            hash[:sort] = [{published: options[:sort]}]
          end
        else
          hash[:sort] = [{published: "desc"}]
        end

        if size
          hash[:from] = 0
          hash[:size] = size
        end

        hash[:query] = {
          bool: {
            filter: {
              bool: {
                should: [
                  {terms: {feed_id: options[:feed_ids]}},
                  {ids: {values: options[:starred_ids]}}
                ]
              }
            }
          }
        }
        if options[:query].present?
          hash[:query][:bool][:must] = {
            query_string: {
              fields: ["title", "title.*", "content", "content.*", "author", "url", "link"],
              quote_field_suffix: ".exact",
              default_operator: "AND",
              allow_leading_wildcard: false,
              query: options[:query]
            }
          }
        end
        if options[:ids].present?
          hash[:query][:bool][:filter][:bool][:must] = {
            ids: {values: options[:ids]}
          }
        end
        if options[:not_ids].present?
          hash[:query][:bool][:filter][:bool][:must_not] = {
            ids: {values: options[:not_ids]}
          }
        end
      end
    end
  end
end
