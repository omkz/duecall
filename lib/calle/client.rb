require "json"
require "net/http"
require "uri"

module Calle
  class Error < StandardError
    attr_reader :details

    def initialize(message, details:)
      super(message)
      @details = details
    end
  end

  class Client
    DEFAULT_BASE_URL = "https://api.heycall-e.com"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20

    def initialize(
      api_key: ENV["CALLE_API_KEY"],
      base_url: ENV.fetch("CALLE_BASE_URL", DEFAULT_BASE_URL)
    )
      @api_key = api_key
      @base_url = base_url
    end

    def create_call(payload:, idempotency_key:)
      raise Error.new("CALL-E API key is not configured.", details: { "error" => "missing_api_key" }) if api_key.to_s.empty?

      response = perform_request(payload, idempotency_key)
      response_data = parse_response(response.body)

      unless response.code.to_i.between?(200, 299)
        raise Error.new(
          "CALL-E request failed.",
          details: {
            "error" => "api_error",
            "http_status" => response.code.to_i,
            "response" => response_data
          }
        )
      end

      unless response_data["id"].is_a?(String) && response_data["id"].present?
        raise Error.new(
          "CALL-E returned an invalid response.",
          details: { "error" => "invalid_response", "response" => response_data }
        )
      end

      response_data
    rescue Error
      raise
    rescue URI::InvalidURIError
      raise Error.new("CALL-E configuration is invalid.", details: { "error" => "invalid_configuration" })
    rescue Timeout::Error, SocketError, SystemCallError, IOError
      raise Error.new("CALL-E could not be reached.", details: { "error" => "connection_error" })
    end

    private
      attr_reader :api_key, :base_url

      def perform_request(payload, idempotency_key)
        uri = URI.join("#{base_url.delete_suffix("/")}/", "v1/calls")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request["Idempotency-Key"] = idempotency_key
        request.body = JSON.generate(payload)

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.request(request) }
      end

      def parse_response(body)
        safe_body = body.to_s.gsub(api_key.to_s, "[FILTERED]")
        JSON.parse(safe_body)
      rescue JSON::ParserError
        { "body" => safe_body.first(1_000) }
      end
  end
end
