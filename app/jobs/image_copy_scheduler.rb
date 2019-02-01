require "sidekiq/api"

class ImageCopyScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  COUNT_KEY = "image_copy_scheduler:count"
  BATCH_SIZE = 100_000

  def perform
    if queue_empty?("image_mover") && start < 1_674_225_632
      enqueue_batch
    end
  end

  private

  def enqueue_batch
    finish = start + BATCH_SIZE
    ids = (start..finish).map { |id| [id] }
    Sidekiq::Client.push_bulk(
      "args" => ids,
      "class" => ImageCopy.name.freeze,
      "queue" => ImageCopy.get_sidekiq_options["queue"].to_s.freeze,
      "retry" => ImageCopy.get_sidekiq_options["retry"].freeze,
    )
    set_finish(finish)
  end

  def start
    @start ||= begin
      result = Sidekiq.redis { |client| client.get(COUNT_KEY) } || 900_000_000
      result.to_i
    end
  end

  def set_finish(finish)
    @increment ||= begin
      Sidekiq.redis { |client| client.set(COUNT_KEY, finish + 1) }
    end
  end

  def queue_empty?(queue)
    @queues ||= Sidekiq::Stats.new.queues
    @queues[queue].blank? || @queues[queue] == 0
  end
end
