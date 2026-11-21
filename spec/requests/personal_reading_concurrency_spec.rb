require "rails_helper"
require "timeout"

RSpec.describe "Concurrent personal reading changes and account withdrawal", type: :request do
  self.use_transactional_tests = false

  let(:password) { "password123!" }
  let!(:user) do
    User.create!(name: "Reader", email: "reading-race-#{SecureRandom.hex(6)}@example.com", password:)
  end
  let!(:book) { Book.create!(title: "Concurrency test book") }

  after do
    Array(@requests).each do |thread|
      thread.kill if thread.alive?
      thread.join
    rescue StandardError
      # The request error is reported by Thread#value in the example.
    end
    user.reload.destroy!
    book.destroy!
    @sticker&.destroy!
  end

  it "does not recreate data when an authenticated add request resumes after withdrawal" do
    authenticated = Queue.new
    resume_add = Queue.new
    allow_any_instance_of(BookshelfEntriesController).to receive(:book_for_create).and_wrap_original do |original|
      selected_book = original.call
      authenticated << true
      resume_add.pop
      selected_book
    end

    add = start_request { |session| session.post(bookshelf_entries_path, params: { book_id: book.id }) }
    Timeout.timeout(15) { authenticated.pop }

    withdrawal = start_request { |session| withdraw(session) }
    expect(Timeout.timeout(15) { withdrawal.value }.status).to eq(303)
    expect(user.reload).to be_withdrawn

    resume_add << true
    response = Timeout.timeout(15) { add.value }
    expect(URI.parse(response.location).path).to eq(root_path)
    expect(user.reload.bookshelves).to be_empty
    expect(user.user_books).to be_empty
    expect(user.bookshelf_entries).to be_empty
    expect(user.book_activities).to be_empty
  end

  it "lets a reading update commit before a waiting withdrawal clears its data" do
    entry = user.bookshelf_entries.create!(book:)
    user_book_id = entry.user_book_id
    @sticker = StickerDefinition.create!(key: "race-#{SecureRandom.hex(6)}", name: "Race sticker")
    update_connection = Queue.new
    resume_update = Queue.new
    allow_any_instance_of(BookshelfEntriesController).to receive(:save_reading_record!).and_wrap_original do |original|
      User.connection_pool.with_connection do |connection|
        update_connection << connection.select_value("SELECT pg_backend_pid()")
      end
      resume_update.pop
      original.call
    end

    withdrawal_connection = Queue.new
    allow_any_instance_of(Users::WithdrawAccount).to receive(:call!).and_wrap_original do |original|
      User.connection_pool.with_connection do |connection|
        withdrawal_connection << connection.select_value("SELECT pg_backend_pid()")
        original.call
      end
    end
    withdrawal_signed_in = Queue.new
    start_withdrawal = Queue.new
    withdrawal = start_request do |session|
      withdrawal_signed_in << true
      start_withdrawal.pop
      withdraw(session)
    end
    Timeout.timeout(15) { withdrawal_signed_in.pop }

    update = start_request do |session|
      session.patch(bookshelf_entry_path(entry), as: :json,
        params: { bookshelf_entry: { status: "reading", sticker_definition_ids: [ @sticker.id ] } })
    end
    update_pid = Timeout.timeout(15) { update_connection.pop }
    start_withdrawal << true
    withdrawal_pid = Timeout.timeout(15) { withdrawal_connection.pop }
    wait_for_blocked_connection(waiter: withdrawal_pid, blocker: update_pid)

    resume_update << true
    update_response, withdrawal_response = Timeout.timeout(15) { [ update.value, withdrawal.value ] }
    expect(update_response.status).to eq(200)
    expect(update_response.parsed_body).to include("status" => "reading", "sticker_definition_ids" => [ @sticker.id ])
    expect(withdrawal_response.status).to eq(303)
    expect(user.reload).to be_withdrawn
    expect(user.bookshelf_entries).to be_empty
    expect(user.user_books).to be_empty
    expect(user.book_activities).to be_empty
    expect(UserBookSticker.where(user_book_id:)).to be_empty
  end

  def start_request
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post(user_session_path, params: { user: { email: user.email, password: } })
        raise "Sign-in failed with status #{session.response.status}" unless session.response.status == 302

        yield session
        session.response
      end
    end
    (@requests ||= []) << thread
    thread
  end

  def withdraw(session)
    session.delete(account_withdrawal_path, params: { account_withdrawal: { current_password: password } })
  end

  def wait_for_blocked_connection(waiter:, blocker:)
    User.uncached do
      User.connection_pool.with_connection do |connection|
        Timeout.timeout(15) do
          until connection.select_value("SELECT #{Integer(blocker)} = ANY(pg_blocking_pids(#{Integer(waiter)}))")
            Thread.pass
          end
        end
      end
    end
  end
end
