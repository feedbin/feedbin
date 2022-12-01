module FeedCrawler
  class EntryFilter
    def self.filter!(*args, **kwargs)
      new(*args, **kwargs).filter
    end

    def initialize(entries, check_for_changes: true, always_check_recent: false, date_filter: nil)
      @entries = entries.first(300)
      @public_ids = @entries.map(&:public_id)
      @check_for_changes = check_for_changes
      @always_check_recent = always_check_recent
      @date_filter = date_filter
      @stats = []
    end

    def filter
      @filter ||= @entries.each_with_object([]) do |entry, array|
        if new?(entry)
          @stats.push(:new)
          array.push(entry.to_entry)
        elsif updated?(entry)
          @stats.push(:updated)
          result = entry.to_entry
          array.push(result)
        else
          @stats.push(:unchanged)
        end
      end
    end

    def stats
      @stats.tally
    end

    private

    def new?(entry)
      return false if in_database?(entry)
      return false if in_cache?(entry)
      return false unless fresh?(entry)
      true
    end

    def updated?(entry)
      return false unless check_for_changes?(entry)
      return false unless in_database?(entry)
      fingerprints[entry.public_id] != entry.fingerprint
    end

    # always check for changes made to articles published within the last 24 hours if @always_check_recent == true
    def check_for_changes?(entry)
      return true if @check_for_changes

      if @always_check_recent && entry.published.present?
        entry.published.after?(24.hours.ago)
      end
    end

    def fresh?(entry)
      return true if @date_filter.nil?
      return true if entry.published.nil?
      entry.published > @date_filter
    end

    def in_database?(entry)
      fingerprints.key?(entry.public_id)
    end

    def in_cache?(entry)
      @previously_created ||= $redis[:refresher].with do |redis|
        redis.mapped_mget(*@public_ids).transform_values { |value| value&.to_i }
      end
      !@previously_created[entry.public_id].nil?
    end

    def fingerprints
      @fingerprints ||= Entry
        .where(public_id: @public_ids)
        .pluck(Arel.sql("public_id, REPLACE(fingerprint::text, '-', '')"))
        .to_h
    end
  end
end