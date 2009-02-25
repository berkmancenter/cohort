class Admin::TagController < Admin::ModelAbstractController
  protect_from_forgery :except => :json_tags

  def edit
    super(:parent_id => params[:parent_id])
  end

  def index
      @tree = Tag.find(:all, :include => [ :children ], :order => :position)
  end

  def json_tags
    tags = Tag.find(:all, :conditions => ["lower(tag) like lower(?)", '%' + params[:search] + '%'], :limit => params[:max] || 20)
    render  :json => tags.collect{|t| {'text' => t.hierarchical_title , 'value' => t['id']}}.to_json 
  end

  protected

  def model
    Tag
  end

end
