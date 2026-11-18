require "rails_helper"
require "timeout"

RSpec.describe "Concurrent bookshelf creation", type: :request do
  self.use_transactional_tests = false

  it "allows only one request to create the last available bookshelf" do
    user = User.create!(name: "Shelf Owner", email: "shelf-race-#{SecureRandom.hex(6)}@example.com", password: "password123!")
    (Bookshelf::MAX_PER_USER - 2).times { |index| user.bookshelves.create!(name: "Shelf #{index}") }

    signed_in = Queue.new
    start = Queue.new
    waiting = Queue.new
    allow_any_instance_of(User).to receive(:lock!).and_wrap_original do |original, *args|
      waiting << original.receiver.id
      original.call(*args)
    end

    requests = []
    %w[First Second].each do |name|
      requests << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post(user_session_path, params: { user: { email: user.email, password: "password123!" } })
          signed_in << session.response.status
          start.pop
          session.post(bookshelves_path, params: { bookshelf: { name:, visibility: "public" } })
          session.response.status
        end
      end
    end
    expect(Timeout.timeout(15) { [ signed_in.pop, signed_in.pop ] }).to eq([ 302, 302 ])

    User.transaction do
      User.lock.find(user.id)
      2.times { start << true }
      expect(Timeout.timeout(15) { [ waiting.pop, waiting.pop ] }).to eq([ user.id, user.id ])
    end

    expect(Timeout.timeout(15) { requests.map(&:value) }.sort).to eq([ 302, 422 ])
    expect(user.bookshelves.count).to eq(Bookshelf::MAX_PER_USER)
    expect(user.bookshelves.default_first.pluck(:position)).to eq((0...Bookshelf::MAX_PER_USER).to_a)
  ensure
    requests&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
    user&.destroy!
  end
end
