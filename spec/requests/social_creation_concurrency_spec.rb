require "rails_helper"
require "timeout"

RSpec.describe "Concurrent like and follow creation", type: :request do
  self.use_transactional_tests = false

  %i[like follow].each do |action|
    it "returns two successful responses and creates one #{action}" do
      suffix = SecureRandom.hex(6)
      password = "password123!"
      reader = User.create!(name: "Reader", email: "social-reader-#{suffix}@example.com", password:)
      author = User.create!(name: "Author", email: "social-author-#{suffix}@example.com", password:)
      if action == :like
        jjaek = author.jjaeks.create!(content: "Public post")
        lock_record = jjaek
        path = jjaek_like_path(jjaek)
        destination = root_path
        records = jjaek.likes.where(user: reader)
      else
        lock_record = reader
        path = user_follow_path(author)
        destination = user_path(author)
        records = reader.active_follows.where(followee: author)
      end

      signed_in = Queue.new
      start = Queue.new
      waiting = Queue.new
      allow_any_instance_of(lock_record.class).to receive(:lock!).and_wrap_original do |original, *args|
        waiting << original.receiver.id
        original.call(*args)
      end

      requests = []
      2.times do
        requests << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            session = ActionDispatch::Integration::Session.new(Rails.application)
            session.post(user_session_path, params: { user: { email: reader.email, password: } })
            signed_in << session.response.status
            start.pop
            session.post(path)
            location = session.response.location
            [ session.response.status, (URI.parse(location).path if location) ]
          end
        end
      end
      expect(Timeout.timeout(15) { [ signed_in.pop, signed_in.pop ] }).to eq([ 302, 302 ])

      lock_record.class.transaction do
        lock_record.class.lock.find(lock_record.id)
        2.times { start << true }
        expect(Timeout.timeout(15) { [ waiting.pop, waiting.pop ] }).to eq([ lock_record.id, lock_record.id ])
      end

      results = Timeout.timeout(15) { requests.map(&:value) }
      expect(results).to eq([ [ 302, destination ], [ 302, destination ] ])
      expect(records.count).to eq(1)
    ensure
      requests&.each do |thread|
        thread.kill if thread.alive?
        thread.join
      end
      reader&.destroy!
      author&.destroy!
    end
  end
end
