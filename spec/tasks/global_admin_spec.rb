require "rails_helper"
require "rake"

RSpec.describe "global_admin tasks" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("global_admin:grant") }

  let!(:admin) { User.create!(name: "Current admin", email: "role-task-admin@example.com", password: "password123!", global_admin: true) }
  let!(:user) { User.create!(name: "Reader", email: "role-task-reader@example.com", password: "password123!") }

  around do |example|
    original_id = ENV["USER_ID"]
    original_email = ENV["EMAIL"]

    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    example.run
  ensure
    ENV["USER_ID"] = original_id
    ENV["EMAIL"] = original_email

    $stdout = original_stdout
    $stderr = original_stderr
  end

  before do
    ENV["USER_ID"] = user.id.to_s
    ENV["EMAIL"] = user.email
    Rake::Task["global_admin:grant"].reenable
    Rake::Task["global_admin:revoke"].reenable
  end

  it "confirms the target and records the server execution for grant and revoke" do
    admin
    allow(Process).to receive(:uid).and_return(1000)
    allow(Etc).to receive(:getpwuid).with(1000).and_return(double(name: "deploy"))
    allow(Socket).to receive(:gethostname).and_return("app-server")
    allow($stdin).to receive(:gets).and_return("Assignment\n", "GRANT #{user.id}\n")

    Rake::Task["global_admin:grant"].invoke
    grant = GlobalAdminRoleChange.find_by!(user: user, action: :grant)
    expect(user.reload).to be_global_admin
    expect(grant).to have_attributes(operator_uid: 1000, operator_account: "deploy", server_hostname: "app-server")
    expect(grant.execution_id).to be_present

    allow($stdin).to receive(:gets).and_return("Staffing change\n", "REVOKE #{user.id}\n")
    Rake::Task["global_admin:revoke"].invoke
    expect(user.reload).not_to be_global_admin
    expect(GlobalAdminRoleChange.find_by!(user: user, action: :revoke).reason).to eq("Staffing change")
  end

  it "rejects mismatched identity, missing reason, and wrong confirmation without an audit row" do
    ENV["USER_ID"] = "not-an-id"
    expect { Rake::Task["global_admin:grant"].invoke }.to raise_error(SystemExit)

    ENV["USER_ID"] = user.id.to_s
    Rake::Task["global_admin:grant"].reenable
    ENV["EMAIL"] = "another@example.com"
    expect { Rake::Task["global_admin:grant"].invoke }.to raise_error(SystemExit)

    ENV["EMAIL"] = user.email
    Rake::Task["global_admin:grant"].reenable
    allow($stdin).to receive(:gets).and_return("\n")
    expect { Rake::Task["global_admin:grant"].invoke }.to raise_error(SystemExit)

    Rake::Task["global_admin:grant"].reenable
    allow($stdin).to receive(:gets).and_return("Assignment\n", "NO\n")
    expect { Rake::Task["global_admin:grant"].invoke }.to raise_error(SystemExit)

    expect(user.reload).not_to be_global_admin
    expect(GlobalAdminRoleChange.where(user: user)).to be_empty
  end
end
