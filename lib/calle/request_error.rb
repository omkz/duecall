module Calle
  class RequestError < Error
    attr_reader :details

    def initialize(message, details: {})
      super(message)
      @details = details
    end
  end
end
