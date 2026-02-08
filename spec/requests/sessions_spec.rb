require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  let!(:user) { User.create!(email: "user@example.com", password: "password123", role: :visitor) }

  describe "GET /login" do
    it "renders the login form" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign In")
    end
  end

  describe "POST /login" do
    context "with valid credentials" do
      it "sets the jwt cookie and returns success message" do
        post login_path, params: { email: user.email, password: "password123" }, as: :json
        expect(response).to have_http_status(:ok)

        expect(response.cookies['jwt']).to be_present
        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("Logged in successfully.")
        expect(json_response["token"]).to be_nil
      end
    end

    context "with invalid credentials" do
      it "returns unauthorized status" do
        post login_path, params: { email: user.email, password: "wrongpassword" }, as: :json
        expect(response).to have_http_status(:unauthorized)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid email or password.")
      end
    end
  end

  describe "DELETE /logout" do
    it "logs the user out by clearing the cookie" do
      delete logout_path, headers: { "Cookie" => "jwt=some_existing_token" }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Logged out.")
      expect(response.headers["Set-Cookie"].join).to include("jwt=")
    end
  end
end
