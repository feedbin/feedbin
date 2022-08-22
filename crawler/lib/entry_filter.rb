# frozen_string_literal: true

class EntryFilter

  def self.filter!(*args, **kwargs)
    new(*args, **kwargs).filter
  end

  def initialize(entries, check_for_updates: true, date_filter: nil)
    @entries = entries
    @check_for_updates = check_for_updates
    @date_filter = date_filter
    unless $redis_alt.nil?
      ids = @entries.first(300).each_with_object([]) do |entry, array|
        content_length = entry.content.respond_to?(:length) ? entry.content.length : 1
        array.push(entry.public_id, content_length)
        unless entry.public_id_alt.nil?
          array.push(entry.public_id_alt, content_length)
        end
      end
      unless ids.empty?
        $redis_alt.with do |connection|
          connection.mset(*ids)
        end
      end
    end
  end

  def filter
    @filter ||= begin
      @entries.first(300).each_with_object([]) do |entry, array|
        if new?(entry)
          array.push(entry.to_entry)
        elsif @check_for_updates && updated?(entry.public_id, entry.content)
          result = entry.to_entry
          result[:update] = true
          array.push(result)
        end
      end
    end
  end

  def fingerprint_entries
    fingerprints = @entries.first(300).each_with_object([]) do |entry, array|
      data = JSON.dump(entry.to_entry)
      fingerprint = Digest::MD5.hexdigest(data)
      array.push("f:#{entry.public_id}", fingerprint)
    end

    return if fingerprints.empty?

    $redis.with do |redis|
      redis.mset(*fingerprints)
    end
  end

  private

  def new?(entry)
    saved_entries[entry.public_id].nil? && fresh?(entry)
  end

  def updated?(public_id, content)
    length = saved_entries[public_id]
    return false if !length
    return false if !content
    return false if length == 1
    content.length != length
  end

  def saved_entries
    @saved_entries ||= $redis.with do |redis|
      keys = @entries.map(&:public_id)
      redis.mapped_mget(*keys).transform_values { |value| value&.to_i }
    end
  end

  def fresh?(entry)
    return true if @date_filter.nil?
    return true if entry.published.nil?
    entry.published > @date_filter
  end
end
