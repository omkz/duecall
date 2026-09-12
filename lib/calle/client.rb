require "cgi"
require "json"
require "net/http"
require "uri"

module Calle
  class Client
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    def initialize(api_key: Rails.application.config.x.calle.api_key,
      base_url: Rails.application.config.x.calle.base_url)
      @api_key = api_key.to_s
      @base_uri = URI.parse(base_url.to_s)

      raise ConfigurationError, "CALL-E API key is not configured" if @api_key.blank?
      unless @base_uri.is_a?(URI::HTTP) && @base_uri.host.present?
        raise ConfigurationError, "CALL-E base URL is invalid"
      end
    rescue URI::InvalidURIError
      raise ConfigurationError, "CALL-E base URL is invalid"
    end

    def create_goal_run(goal_id:, phone:, variables:, idempotency_key:)
      uri = goal_run_uri(goal_id)
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request["Idempotency-Key"] = idempotency_key
      request.body = JSON.generate(phone: phone, variables: variables)

      response = perform(request, uri)
      response_body = response.body
      body = parse_body(response_body)
      unless response.code.to_i == 201
        raise RequestError.new(
          "CALL-E rejected the Goal Run submission with HTTP #{response.code}",
          details: { "http_status" => response.code.to_i, "response" => body }
        )
      end

      unless body.is_a?(Hash) && body["id"].present?
        raise RequestError.new(
          "CALL-E accepted the Goal Run but returned no Goal Run ID",
          details: { "http_status" => response.code.to_i, "response" => body }
        )
      end

      body
    rescue JSON::ParserError => error
      raise invalid_json_error(error, response_body)
    rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => error
      raise request_error("submission", error)
    end

    def get_goal_run(goal_id:, goal_run_id:)
      raise ConfigurationError, "CALL-E Goal Run ID is required" if goal_run_id.blank?

      uri = goal_run_uri(goal_id, goal_run_id:)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"

      response = perform(request, uri)
      response_body = response.body
      body = parse_body(response_body)
      unless response.code.to_i == 200
        raise RequestError.new(
          "CALL-E rejected the Goal Run fetch with HTTP #{response.code}",
          details: { "http_status" => response.code.to_i, "response" => body }
        )
      end

      unless body.is_a?(Hash) && body["id"] == goal_run_id
        raise RequestError.new(
          "CALL-E returned an unexpected Goal Run",
          details: { "http_status" => response.code.to_i, "response" => body }
        )
      end

      body
    rescue JSON::ParserError => error
      raise invalid_json_error(error, response_body)
    rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => error
      raise request_error("fetch", error)
    end

    private
      def perform(request, uri)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) do |http|
          http.request(request)
        end
      end

      def goal_run_uri(goal_id, goal_run_id: nil)
        raise ConfigurationError, "CALL-E overdue invoice Goal ID is not configured" if goal_id.blank?

        uri = @base_uri.dup
        base_path = uri.path.to_s.delete_suffix("/")
        escaped_goal_id = CGI.escape(goal_id.to_s).gsub("+", "%20")
        uri.path = "#{base_path}/v1/goals/#{escaped_goal_id}/runs"
        if goal_run_id
          escaped_goal_run_id = CGI.escape(goal_run_id.to_s).gsub("+", "%20")
          uri.path = "#{uri.path}/#{escaped_goal_run_id}"
        end
        uri.query = nil
        uri.fragment = nil
        uri
      end

      def parse_body(body)
        return {} if body.blank?

        JSON.parse(body)
      end

      def invalid_json_error(error, response_body)
        RequestError.new(
          "CALL-E returned invalid JSON",
          details: {
            "error_class" => error.class.name,
            "error_message" => error.message,
            "response_body" => response_body
          }
        )
      end

      def request_error(action, error)
        RequestError.new(
          "CALL-E Goal Run #{action} failed: #{error.message}",
          details: { "error_class" => error.class.name, "error_message" => error.message }
        )
      end
  end
end
