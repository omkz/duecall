require "rails_helper"

RSpec.describe Calle::Client do
  describe "#create_goal_run" do
    let(:response) do
      instance_double(
        Net::HTTPCreated,
        code: "201",
        body: JSON.generate(object: "goal_run", id: "rgrp_invoice_123", status: "queued")
      )
    end
    let(:http) { instance_double(Net::HTTP) }

    it "submits the documented Goal Run request" do
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq("/v1/goals/goal_overdue/runs")
        expect(request["Authorization"]).to eq("Bearer secret")
        expect(request["Content-Type"]).to eq("application/json")
        expect(request["Idempotency-Key"]).to eq("attempt-123")
        expect(JSON.parse(request.body)).to eq(
          "phone" => "+628123456789",
          "variables" => { "invoice_number" => "INV-001" }
        )
        response
      end

      result = described_class.new(api_key: "secret", base_url: "https://api.example.test").create_goal_run(
        goal_id: "goal_overdue",
        phone: "+628123456789",
        variables: { invoice_number: "INV-001" },
        idempotency_key: "attempt-123"
      )

      expect(result["id"]).to eq("rgrp_invoice_123")
    end

    it "raises a request error containing the provider response on rejection" do
      rejected_response = instance_double(
        Net::HTTPUnprocessableEntity,
        code: "422",
        body: JSON.generate(error: { code: "invalid_variables", message: "amount is required" })
      )
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(rejected_response)

      expect do
        described_class.new(api_key: "secret", base_url: "https://api.example.test").create_goal_run(
          goal_id: "goal_overdue",
          phone: "+628123456789",
          variables: {},
          idempotency_key: "attempt-123"
        )
      end.to raise_error(Calle::RequestError) { |error|
        expect(error.details).to eq(
          "http_status" => 422,
          "response" => { "error" => { "code" => "invalid_variables", "message" => "amount is required" } }
        )
      }
    end
  end
end
