require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
ENV["VIPS_WARNING"] ||= "1"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include Devise::Test::IntegrationHelpers, type: :request

  # Chrome rejects the wildcard origin in Capybara's storage reset.
  config.prepend_after(:example, type: :system) do
    # Read Capybara's existing state without creating a session or driver.
    session_key = "#{Capybara.current_driver}:#{Capybara.session_name}:#{Capybara.app.object_id}"
    session = Capybara.send(:session_pool).fetch(session_key, nil)
    driver = session&.instance_variable_get(:@driver)
    next unless driver.is_a?(Capybara::Selenium::Driver) && driver.options[:browser] == :chrome

    # Report server errors before quit clears them and Rails resets the sessions.
    begin
      session.server&.wait_for_pending_requests
      session.raise_server_error!
    ensure
      session.quit
    end
  end
end
