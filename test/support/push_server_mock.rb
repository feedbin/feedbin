class PushServerMock
  attr_reader :status, :count

  def initialize(status)
    @status = status
    @count = 0
  end

  def with
    yield self
  end

  def prepare_push(notification)
    ResponseMock.new(@status, notification)
  end

  def join
    true
  end

  def push_async(notification)
    @count += 1
    true
  end

  class ResponseMock
    def initialize(status, notification)
      @status = status
      @notification = notification
    end

    attr_reader :status

    def body
      {"reason" => "BadDeviceToken"}
    end

    def headers
      {"apns-id" => @notification.apns_id}
    end

    def on(event)
      yield self
    end
  end
end
