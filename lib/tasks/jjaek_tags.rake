namespace :jjaek_tags do
  desc "Backfill and reconcile hashtag links for existing Jjaeks"
  task backfill: :environment do
    Jjaek.find_each do |jjaek|
      jjaek.with_lock { jjaek.refresh_tags! }
    end
  end
end
