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

  describe "#get_goal_run" do
    let(:http) { instance_double(Net::HTTP) }

    it "fetches the public Goal Run by its Goal Run ID" do
      response = instance_double(
        Net::HTTPOK,
        code: "200",
        body: JSON.generate(
          object: "goal_run",
          id: "rgrp_invoice_123",
          run_id: "run_invoice_123",
          call_id: nil,
          status: "in_progress",
          result: nil,
          error: nil
        )
      )
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Get)
        expect(request.path).to eq("/v1/goals/goal_overdue/runs/rgrp_invoice_123")
        expect(request["Authorization"]).to eq("Bearer secret")
        expect(request["Accept"]).to eq("application/json")
        response
      end

      result = described_class.new(api_key: "secret", base_url: "https://api.example.test").get_goal_run(
        goal_id: "goal_overdue",
        goal_run_id: "rgrp_invoice_123"
      )

      expect(result["id"]).to eq("rgrp_invoice_123")
      expect(result["run_id"]).to eq("run_invoice_123")
    end

    it "raises a request error containing the provider response on failure" do
      response = instance_double(
        Net::HTTPNotFound,
        code: "404",
        body: JSON.generate(error: { code: "goal_run_not_found" })
      )
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      expect do
        described_class.new(api_key: "secret", base_url: "https://api.example.test").get_goal_run(
          goal_id: "goal_overdue",
          goal_run_id: "rgrp_missing"
        )
      end.to raise_error(Calle::RequestError) { |error|
        expect(error.details).to eq(
          "http_status" => 404,
          "response" => { "error" => { "code" => "goal_run_not_found" } }
        )
      }
    end
  end
end
