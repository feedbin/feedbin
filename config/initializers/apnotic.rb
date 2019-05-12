module Apnotic
  class Connection
    private
    def remote_max_concurrent_streams
      if @client.remote_settings[:settings_max_concurrent_streams] == 0x7fffffff
        1
      else
        @client.remote_settings[:settings_max_concurrent_streams]
      end
    end
  end
end