module ActivityPub
  class Flatten

    include ActivityHelper

    def self.flatten(data)
      new(data).flatten
    end

    def flatten
      # import_objects
      download_objects
      activities = load_activities
      combine_objects(activities)
    end

    def initialize(data)
      @data = data
    end

    def combine_objects(activities)
      items.each_with_object([]) do |item, array|
        actor = activities.dig(item["actor"])

        next if actor.nil?

        item["actor"] = actor.data

        object = item.dig("object")
        if item.dig("object").is_a?(String)
          object = activities.dig(object)&.data
        end

        next if object.nil?

        attributed_to_url = value_or_id(first_of_value(object["attributedTo"]))
        attributed_to = activities.dig(attributed_to_url)

        # make sure to check if there is an expanded object here. This could just be an array of strings
        # or objects with a name field: https://www.w3.org/TR/activitystreams-vocabulary/#dfn-attributedto
        unless attributed_to.nil?
          object["attributedTo"] = attributed_to.data
        end

        item["object"] = object

        array.push(item)
      end
    end

    def load_activities
      activities = Activity.where(url: object_urls).index_by(&:url)
      additional_actors = activities.filter_map do |url, activity|
        value_or_id(first_of_value(activity.data.dig("attributedTo")))
      end.uniq
      actors = Activity.where(url: additional_actors).index_by(&:url)
      activities.merge(actors)
    end

    # Think about importing only if the object id matches the host
    # Otherwise it would be possible to claim to belong to another user
    # def import_objects
    #   activities = items.each_with_object([]) do |item, array|
    #     object = item.dig("object")
    #     next unless object.is_a?(Hash)
    #     next unless type = object.dig("type")
    #     next unless id = object.dig("id")
    #     activity = Activity.new(activity_type: type, url: id, data: object)
    #     array.push(activity)
    #   end
    #   Activity.import!(activities, on_duplicate_key_update: {conflict_target: :url, columns: [:data]})
    # end

    def download_objects
      batch = Sidekiq::Batch.new
      batch.jobs do
        object_urls.each do |object_url|
          SaveObject.perform_async(object_url)
        end
      end

      # hack around lack of test support for batch
      return if Rails.env.test?

      status = Sidekiq::Batch::Status.new(batch.bid)
      status.join
    end

    def object_urls
      items.each_with_object([]) do |item, array|
        if actor = item.dig("actor")
          array.push(actor)
        end
        if object = item.dig("object")
          array.push(object) if object.is_a?(String)
        end
      end.uniq
    end

    def items
      @data.dig("orderedItems").select do |item|
        ["Announce", "Create"].include?(item&.dig("type"))
      end
    end
  end
end