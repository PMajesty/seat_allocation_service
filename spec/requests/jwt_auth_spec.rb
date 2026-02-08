require 'rails_helper'

class JwtTestController < ActionController::Base
  include Authenticatable

  before_action :authenticate_user!

  def test_auth
    render json: { message: "Authenticated", user_id: current_user.id }
  end
end

RSpec.describe "JWT Authentication", type: :request do
  before do
    Rails.application.routes.draw do
      get "/test_auth" => "jwt_test#test_auth"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  let(:user) { User.create!(email: "jwt@example.com", password: "password123") }
  let(:headers) { jwt_headers(user) }

  describe "Access Control" do
    context "with valid token" do
      it "allows access" do
        get "/test_auth", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Authenticated")
        expect(json["user_id"]).to eq(user.id)
      end
    end

    context "with missing token" do
      it "returns unauthorized" do
        get "/test_auth", as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid token" do
      it "returns unauthorized for malformed token" do
        get "/test_auth", headers: { "Authorization" => "Bearer invalid.token.garbage" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns unauthorized for wrong secret signature" do
        fake_token = JWT.encode({ user_id: user.id }, "wrong_secret", "HS256")
        get "/test_auth", headers: { "Authorization" => "Bearer #{fake_token}" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with expired token" do
      it "returns unauthorized" do
        payload = {
          user_id: user.id,
          ver: user.token_version,
          exp: 1.minute.ago.to_i,
          iss: JwtService::ISSUER,
          aud: JwtService::AUDIENCE
        }
        expired_token = JWT.encode(payload, JwtService::KEYS[JwtService::ACTIVE_KID], JwtService::ALGORITHM, { kid: JwtService::ACTIVE_KID })

        get "/test_auth", headers: { "Authorization" => "Bearer #{expired_token}" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid issuer" do
      it "returns unauthorized" do
        payload = { user_id: user.id, ver: user.token_version, iss: "evil-site" }
        token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

        get "/test_auth", headers: { "Authorization" => "Bearer #{token}" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "Token Revocation" do
    it "rejects token after user invalidates tokens" do
      get "/test_auth", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      user.invalidate_tokens!

      get "/test_auth", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      new_headers = jwt_headers(user.reload)
      get "/test_auth", headers: new_headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "rejects token after password change" do
      get "/test_auth", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      user.update!(password: "new_secure_password")

      get "/test_auth", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
