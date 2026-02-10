require 'rails_helper'

RSpec.describe CleanupSimulationWorker do
  it "deletes simulation users" do
    User.create!(email: "keep@example.com", password: "password")
    User.create!(email: "sim_1@simulation.local", password: "password")
    User.create!(email: "sim_2@simulation.local", password: "password")

    expect {
      described_class.new.perform
    }.to change(User, :count).by(-2)

    expect(User.exists?(email: "keep@example.com")).to be true
    expect(User.exists?(email: "sim_1@simulation.local")).to be false
  end
end
