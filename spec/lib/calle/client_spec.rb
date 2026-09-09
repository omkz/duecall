require "rails_helper"

RSpec.describe Calle::Client do
  describe "#create_call" do
    it "posts JSON to CALL-E with authentication and an idempotency key" do
      response = instance_double(Net::HTTPResponse, code: "201", body: '{"id":"call_123","status":"queued"}')
      http = instance_double(Net::HTTP)
      captured_request = nil

      expect(Net::HTTP).to receive(:start).with(
        "api.heycall-e.com",
        443,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 20
      ).and_yield(http)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      payload = { task: "Call about INV-001", recipients: [ { phones: [ "+628123456789" ] } ] }
      result = described_class.new(api_key: "secret-key").create_call(
        payload: payload,
        idempotency_key: "duecall-call-attempt-42"
      )

      expect(result).to include("id" => "call_123")
      expect(captured_request.path).to eq("/v1/calls")
      expect(captured_request["Authorization"]).to eq("Bearer secret-key")
      expect(captured_request["Content-Type"]).to eq("application/json")
      expect(captured_request["Idempotency-Key"]).to eq("duecall-call-attempt-42")
      expect(JSON.parse(captured_request.body)).to eq(JSON.parse(payload.to_json))
    end

    it "fails before HTTP when the API key is missing" do
      expect(Net::HTTP).not_to receive(:start)

      expect do
        described_class.new(api_key: nil).create_call(payload: { task: "Call" }, idempotency_key: "key-1")
      end.to raise_error(Calle::Error) { |error|
        expect(error.details).to eq("error" => "missing_api_key")
      }
    end

    it "filters the API key from provider error details" do
      response = instance_double(
        Net::HTTPResponse,
        code: "401",
        body: '{"error":"Authorization Bearer secret-key was rejected"}'
      )
      http = instance_double(Net::HTTP)

      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      expect do
        described_class.new(api_key: "secret-key").create_call(payload: { task: "Call" }, idempotency_key: "key-1")
      end.to raise_error(Calle::Error) { |error|
        expect(error.message).not_to include("secret-key")
        expect(error.details.to_json).not_to include("secret-key")
      }
    end
  end
end
