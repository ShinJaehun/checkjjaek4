class RelationshipsController < ApplicationController
  include RelationshipManagement

  def index
    relationship_page
    render :index, formats: [ :html ]
  end
end
