require 'rails_helper'

RSpec.describe "Registrations", type: :request do
  describe "GET /signup" do
    it "renders the signup form" do
      get signup_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Account")
    end
  end

  describe "POST /signup" do
    context "with valid parameters" do
      let(:valid_params) do
        { user: { email: "test@example.com", password: "password123", password_confirmation: "password123" } }
      end

      it "creates a new user" do
        expect {
          post signup_path, params: valid_params, as: :json
        }.to change(User, :count).by(1)
      end

      it "sets the jwt cookie and returns success message" do
        post signup_path, params: valid_params, as: :json
        expect(response).to have_http_status(:created)

        expect(response.cookies['jwt']).to be_present
        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("Account created successfully.")
        expect(json_response["token"]).to be_nil
      end

      it "sets the user role to visitor" do
        post signup_path, params: valid_params, as: :json
        expect(User.last.role).to eq("visitor")
      end
    end

    context "with invalid parameters" do
      let(:invalid_params) do
        { user: { email: "invalid", password: "123", password_confirmation: "456" } }
      end

      it "does not create a user" do
        expect {
          post signup_path, params: invalid_params, as: :json
        }.not_to change(User, :count)
      end

      it "returns errors" do
        post signup_path, params: invalid_params, as: :json
        expect(response).to have_http_status(:unprocessable_content)

        json_response = JSON.parse(response.body)
        expect(json_response["errors"]).to be_present
      end
    end
  end
end
