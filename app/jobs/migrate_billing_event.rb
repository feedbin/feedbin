class MigrateBillingEvent
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(id = nil, schedule = false)
    if schedule
      build
    else
      update(id)
    end
  end

  def update(id)
    event = BillingEvent.find(id)
    event.update_attribute(:info, event.details.as_json)
  end

  def build
    BillingEvent.select(:id).find_in_batches(batch_size: 10_000) do |records|
      Sidekiq::Client.push_bulk(
        'args'  => records.map{ |record| record.attributes.values },
        'class' => self.class.name,
        'queue' => 'worker_slow',
        'retry' => false
      )
    end
  end

end