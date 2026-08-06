module Search
  class TouchActions
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    # find raises unless every id resolves, and it raises before touching any
    # of them — so one action destroyed between the enqueue and the perform
    # would cost the whole batch its percolator refresh.
    def perform(action_ids)
      # where/find_each rather than find: an action deleted between enqueue and
      # perform would otherwise raise RecordNotFound and fail the whole job.
      Action.where(id: action_ids).find_each do |action|
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