class AddPublicationMetadataToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :published_on, :date
    add_column :books, :translators_text, :string
  end
end
