module Search
  class TouchActions
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(action_ids)
      actions = Action.find(action_ids)
      actions.each do |action|
        # Ask for validity first, then set automatic_modification: without it
        # the "select at least one feed or tag" validation rejects exactly the
        # case this job exists for — the last tagging was removed — and the
        # save fails silently, leaving a stale percolator behind.
        action.status = if action.invalid?
          Action.statuses[:broken]
        else
          Action.statuses[:active]
        end
        action.automatic_modification = true
        action.save!
      end
    end
  end
end