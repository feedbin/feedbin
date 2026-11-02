class PushServerMock
  attr_reader :status, :count, :delivered, :topics

  def initialize(status, reason: "BadDeviceToken")
    @status = status
    @reason = reason
    @count = 0
    # token => alert title, so a test can check what each recipient was sent
    @delivered = {}
    # token => APNs topic (the app's bundle id)
    @topics = {}
  end

  def with
    yield self
  end

  def prepare_push(notification)
    @delivered[notification.token] = notification.alert[:title]
    @topics[notification.token] = notification.topic
    ResponseMock.new(@status, notification, @reason)
  end

  def join
    true
  end

  def push_async(notification)
    @count += 1
    true
  end

  class ResponseMock
    def initialize(status, notification, reason)
      @status = status
      @notification = notification
      @reason = reason
    end

    attr_reader :status

    def body
      {"reason" => @reason}
    end

    def headers
      {"apns-id" => @notification.apns_id}
    end

    def on(event)
      yield self
    end
  end
end
