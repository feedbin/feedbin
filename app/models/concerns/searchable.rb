module Searchable
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    UNREAD_REGEX = /(?<=\s|^)is:\s*unread(?=\s|$)/
    READ_REGEX = /(?<=\s|^)is:\s*read(?=\s|$)/
    STARRED_REGEX = /(?<=\s|^)is:\s*starred(?=\s|$)/
    UNSTARRED_REGEX = /(?<=\s|^)is:\s*unstarred(?=\s|$)/
    SORT_REGEX = /(?<=\s|^)sort:\s*(asc|desc|relevance)(?=\s|$)/i
    TAG_ID_REGEX = /(?<=\s|^)tag_id:\s*([0-9]+)(?=\s|$)/

    search_settings = {
      "analysis": {
        "analyzer": {
          "lower_exact": {
            "tokenizer": "whitespace",
            "filter":  ["lowercase"]
          }
        }
      }
    }

    settings search_settings do
      mappings do
        indexes :id, type: "long", index: :not_analyzed
        indexes :title, analyzer: "snowball", fields: {exact: {type: "string", analyzer: "lower_exact"}}
        indexes :content, analyzer: "snowball", fields: {exact: {type: "string", analyzer: "lower_exact"}}
        indexes :emoji, analyzer: "whitespace", fields: {exact: {type: "string", analyzer: "whitespace"}}
        indexes :author, analyzer: "lower_exact", fields: {exact: {type: "string", analyzer: "lower_exact"}}
        indexes :url, analyzer: "keyword", fields: {exact: {type: "string", analyzer: "keyword"}}
        indexes :feed_id, type: "long", index: :not_analyzed, include_in_all: false
        indexes :published, type: "date", include_in_all: false
        indexes :updated, type: "date", include_in_all: false

        indexes :twitter_screen_name, analyzer: "whitespace"
        indexes :twitter_name, analyzer: "whitespace"
        indexes :twitter_retweet, type: "boolean"
        indexes :twitter_media, type: "boolean"
        indexes :twitter_image, type: "boolean"
        indexes :twitter_link, type: "boolean"
      end
    end

    def self.saved_search_count(user)
      saved_searches = user.saved_searches
      if saved_searches.length < 10
        unread_entries = user.unread_entries.pluck(:entry_id)
        searches = build_multi_search(user, saved_searches)
        queries = searches.map do |search|
          {
            index: Entry.index_name,
            search: search.query,
          }
        end

        if queries.present?
          result = Entry.__elasticsearch__.client.msearch body: queries
          entry_ids = result["responses"].map do |response|
            hits = response.dig("hits", "hits") || []
            hits.map do |hit|
              hit["_id"].to_i
            end
          end
          search_ids = searches.map { |search| search.id }
          Hash[search_ids.zip(entry_ids)]
        else
          nil
        end
      end
    end

    def self.build_multi_search(user, saved_searches)
      saved_searches.map do |saved_search|
        query_string = saved_search.query

        next if query_string =~ READ_REGEX

        query_string = query_string.gsub(UNREAD_REGEX, "")
        query_string = {query: "#{query_string} is:unread"}
        options = build_search(query_string, user)
        options[:size] = 50

        query = build_query(options)
        query[:fields] = ["id", "feed_id"]

        OpenStruct.new({id: saved_search.id, query: query})
      end.compact
    end

    def self.scoped_search(params, user)
      options = build_search(params, user)
      query = build_query(options)
      Entry.search(query).page(params[:page]).records(includes: :feed)
    end

    def self.build_query(options)
      Hash.new.tap do |hash|
        hash[:fields] = ["id"]
        if options[:sort]
          if %w{desc asc}.include?(options[:sort])
            hash[:sort] = [{published: options[:sort]}]
          end
        else
          hash[:sort] = [{published: "desc"}]
        end

        if size = options[:size]
          hash[:from] = 0
          hash[:size] = size
        end

        hash[:query] = {
          bool: {
            filter: {
              bool: {
                should: [
                  {terms: {feed_id: options[:feed_ids]}},
                  {terms: {id: options[:starred_ids]}},
                ],
              },
            },
          },
        }
        if options[:query].present?
          hash[:query][:bool][:must] = {
            query_string: {
              fields: ["title", "content", "emoji", "author", "url"],
              default_operator: "AND",
              quote_field_suffix: ".exact",
              query: options[:query],
            },
          }
        end
        if options[:ids].present?
          hash[:query][:bool][:filter][:bool][:must] = {
            terms: {id: options[:ids]},
          }
        end
        if options[:not_ids].present?
          hash[:query][:bool][:filter][:bool][:must_not] = {
            terms: {id: options[:not_ids]},
          }
        end
      end
    end

    def self.build_search(params, user)
      if params[:query].respond_to?(:gsub)
        params[:query] = params[:query].gsub("body:", "content:")
      end

      if params[:query] =~ UNREAD_REGEX
        params[:query] = params[:query].gsub(UNREAD_REGEX, "")
        params[:read] = false
      elsif params[:query] =~ READ_REGEX
        params[:query] = params[:query].gsub(READ_REGEX, "")
        params[:read] = true
      end

      if params[:query] =~ STARRED_REGEX
        params[:query] = params[:query].gsub(STARRED_REGEX, "")
        params[:starred] = true
      elsif params[:query] =~ UNSTARRED_REGEX
        params[:query] = params[:query].gsub(UNSTARRED_REGEX, "")
        params[:starred] = false
      end

      if params[:query] =~ SORT_REGEX
        params[:sort] = params[:query].match(SORT_REGEX)[1].downcase
        params[:query] = params[:query].gsub(SORT_REGEX, "")
      end

      if params[:query] =~ TAG_ID_REGEX
        tag_id = params[:query].match(TAG_ID_REGEX)[1].downcase
        feed_ids = user.taggings.where(tag_id: tag_id).pluck(:feed_id)

        id_string = feed_ids.join(" OR ")
        id_string = "feed_id:(#{id_string})"

        params[:query] = params[:query].gsub(TAG_ID_REGEX, id_string)
      end

      params[:query] = FeedbinUtils.escape_search(params[:query])

      options = {
        query: params[:query],
        sort: "desc",
        starred_ids: [],
        ids: [],
        not_ids: [],
        feed_ids: [],
      }

      if params[:sort] && %w{desc asc relevance}.include?(params[:sort])
        options[:sort] = params[:sort]
      end

      if params[:read] == false
        ids = [0]
        ids.concat(user.unread_entries.pluck(:entry_id))
        options[:ids].push(ids)
      elsif params[:read] == true
        options[:not_ids].push(user.unread_entries.pluck(:entry_id))
      end

      if params[:starred] == true
        options[:ids].push(user.starred_entries.pluck(:entry_id))
      elsif params[:starred] == false
        options[:not_ids].push(user.starred_entries.pluck(:entry_id))
      end

      if params[:feed_ids].present?
        subscribed_ids = user.subscriptions.pluck(:feed_id)
        requested_ids = params[:feed_ids]
        options[:feed_ids] = (requested_ids & subscribed_ids)
      else
        options[:feed_ids] = user.subscriptions.pluck(:feed_id)
        options[:starred_ids] = user.starred_entries.pluck(:entry_id)
      end

      if options[:ids].present?
        options[:ids] = options[:ids].inject(:&)
      end

      if options[:not_ids].present?
        options[:not_ids] = options[:not_ids].flatten.uniq
      end
      options
    end

  end
end
