class Admin::ContactController < Admin::ModelAbstractController

  def show
    begin
      @contact = Contact.find(params[:id])
    rescue Exception => exc
      flash[:error] = "There was an error when we looked for that contact: #{exc.message}"
      redirect_to :action => :dashboard and return
    end
  end

  def dashboard
  end

  def manage_notes
    @contact = Contact.find(params[:id])
    render :partial => 'shared/manage_notes', :layout => (request.xhr? ? false : true)
  end

  def manage_tags
    @object = self.model.find_by_id(params[:id])
    if request.post?
      new_tags = []
      current_tags = (params[:contact] ? params[:contact][:tag_ids] : [])
      parse_tag_list(:tags_to_parse => params[:new_tags],:tag_list => new_tags, :autocreate => true)
      deduped_tags = [
        (new_tags and new_tags.collect{|t|t.to_i}),
        (current_tags and current_tags.collect{|t|t.to_i})
      ].flatten.uniq.compact
      logger.warn('Deduped Tags: ' + deduped_tags.inspect)
      @object.tag_ids = deduped_tags || []
      @object.save
    end
    render :partial => 'shared/manage_tags', :layout => (request.xhr? ? false : true), :locals => {:contact_line => @object, :standalone => true}
  end

  def edit
    model = self.model
    @object = model.find_by_id(params[:id]) || model.new

    #Copy the object to a class-specific instance variable so we can have easier-to-use edit and management forms.
    self.instance_variable_set('@' + @object.class.name.downcase, @object)
    if request.post?
      @object.attributes = params[@object.class.name.downcase]
      current_tags = params[:contact][:tag_ids]

      new_tags = []
      parse_tag_list(:tags_to_parse => params[:new_tags],:tag_list => new_tags, :autocreate => true)
      emails = deal_with_email @object
      addresses = deal_with_addresses @object
      new_notes = deal_with_notes @object

      deduped_tags = [
        (new_tags and new_tags.collect{|t|t.to_i}),
        (current_tags and current_tags.collect{|t|t.to_i})
      ].flatten.uniq.compact

      #logger.warn('Deduped Tags: ' + deduped_tags.inspect)

      @object.tag_ids = deduped_tags || []

      @object.notes << new_notes

      if flash[:ceerror].blank? and flash[:caerror].blank? and @object.save
        unless emails.blank?
          emails.each do |em|
            unless @object.contact_emails.exists?(em)
              @object.contact_emails << em
            end
          end
        end
        unless addresses.blank?
          addresses.each do |ca|
            unless @object.contact_addresses.exists?(ca)
              @object.contact_addresses << ca
            end
          end
        end
        @existing_addresses_to_destroy.each{|ca|ca.destroy}
        @object.contact_addresses.each{|ca|
          ca.save
        }
        @existing_emails_to_destroy.each{|e|e.destroy}
        @object.contact_emails.each{|ce|
          ce.save
        }
        redirect_to :action => :index and return
      else
        logger.warn(@object.errors.inspect)
      end
    end
  end

  def index
    add_to_sortable_columns('contacts', :model => Contact, :field => :last_name, :alias => :last_name)
    add_to_sortable_columns('contacts', :model => Contact, :field => :updated_at, :alias => :updated_at)
    add_to_sortable_columns('contacts', :model => Contact, :field => :country, :alias => :country)
    add_to_sortable_columns('contacts', :model => Contact, :field => :state, :alias => :state)
    ferret_fields = (params[:q].blank? ? '*' : params[:q]) + ' '

    if params[:tags_to_include] or params[:included_tags]
      include_tags = []
      existing_included_tags = params[:included_tags]
      parse_tag_list(:tags_to_parse => params[:tags_to_include] || '', :tag_list => include_tags, :autocreate => false)
      @included_tags_for_output = [existing_included_tags,include_tags].flatten.uniq.compact.collect{|tid| Tag.find(tid.to_i)} ||[]

      tags_to_search_for = []
      @included_tags_for_output.each do |tag|
        tags_to_search_for << tag.descendants
      end
      final_tags_to_include = [tags_to_search_for,@included_tags_for_output].flatten.uniq.compact
      unless final_tags_to_include.blank?
        ferret_fields += " (" + (final_tags_to_include.collect{|tid| "my_tag_ids:#{tid.id}"}.join(' OR ')) + ") "
      end
    end

    if params[:tags_to_exclude] or params[:excluded_tags]
      exclude_tags = []
      @excluded_tags_for_output = []
      existing_excluded_tags = params[:excluded_tags]
      parse_tag_list(:tags_to_parse => params[:tags_to_exclude], :tag_list => exclude_tags, :autocreate => false)
      @excluded_tags_for_output = [existing_excluded_tags,exclude_tags].flatten.uniq.compact.collect{|tid| Tag.find(tid.to_i)} ||[]
      tags_to_exclude = []
      @excluded_tags_for_output.each do |tag|
        tags_to_exclude << tag.descendants
      end
      final_tags_to_exclude = [@excluded_tags_for_output,tags_to_exclude].flatten.uniq.compact
      unless final_tags_to_exclude.blank?
        ferret_fields += ' (' + (final_tags_to_exclude.collect{|tid| "-my_tag_ids:#{tid.id}"}.join(' OR ')) + ') '
      end
    end

    #logger.warn("Ferret search string: " + ferret_fields)

    if params[:export].blank?
      if ferret_fields == '* '
        @contacts = Contact.paginate(:page => params[:page],:per_page => 50,:include => [:notes, :contact_emails,:tags], :order => sortable_order('contacts',:model => Contact,:field => 'updated_at',:sort_direction => :desc))
      else
        @contacts = Contact.find_with_ferret(ferret_fields, {:page => params[:page],:per_page => 50},{:order => sortable_order('contacts',:model => Contact,:field => 'updated_at',:sort_direction => :desc) })
      end
      render :layout => (request.xhr? ? false : true)
    else
      contacts = Contact.find_with_ferret(ferret_fields)
      columns = Contact.columns.collect{|c|c.name}
      if params[:export] == 'csv'
        #De-normalize data because csv files can't be hierarchical like XML.
        additional_columns = ['primary_email','other_emails']
        columns << additional_columns
        columns.flatten!
        contacts.each do |c|
          emails = c.contact_emails.collect{|ce| ce.email}
          c['primary_email'] = c.primary_email
          emails.delete(c.primary_email)
          c['other_emails'] = emails.join(',')
        end
        render_csv(:model => Contact, :objects => contacts, :columns => columns)
      else
        render :xml => contacts.to_xml(:include => [:contact_emails, :notes, :tags])
      end
    end
  end

  protected
  def model
    Contact
  end

  def deal_with_notes(object)
    notes_to_add = []
    if params[:note] && ! params[:note][:note].blank?
      note_to_add = Note.new(:user => @session_user,:contact => object)
      note_to_add.attributes = params[:note]
      if ! note_to_add.valid?
        object.errors.add_to_base(note_to_add.errors.collect{|attribute,msg| "#{attribute}  #{msg}"}.join('<br/>'))
        flash[:error] = (flash[:ceerror].blank? ? '' : flash[:ceerror]) + note_to_add.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>')
      end
      notes_to_add << note_to_add
    end
    return notes_to_add
  end

  def deal_with_email(object)
    flash[:ceerror] = nil
    number_new_emails = params[:new_emails]
    existing_emails = params[:contact_email_ids]
    new_emails = []
    existing_emails = []
    @existing_emails_to_destroy = []
    deduped_emails = []

    #so we need to:
    # Delete existing emails that've been checked as needing deletion
    # Add the new addresses, with some error checking.
    # Ensure that only one address is a primary, across both the new and old addresses.
    # I suspect this will be much easier in rails 2.3 because of the :autosave association attribute.
    #
    new_email_is_primary = nil

    number_new_emails.each{|i|
      unless params[:new_email][i][:email].blank?
        new_email = {
          :email => params[:new_email][i][:email],
          :email_type => params[:new_email][i][:email_type],
          :is_primary => ((params[:new_email][:is_primary] == i) ? true : false),
          :contact => object
        }
        #logger.warn(new_email.inspect + "\n")
        ce = ContactEmail.new(new_email)
        if ! ce.valid?
          object.errors.add_to_base(ce.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>'))
          flash[:ceerror] = (flash[:ceerror].blank? ? '' : flash[:ceerror]) + ce.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>')
        else
          if ce.is_primary
            new_email_is_primary = true
          end
          deduped_emails << ce
        end
      end
    }

    existing_email_is_primary = nil
    object.contact_emails.each{|ce|
      if params[:contact_email][ce.id.to_s][:delete].to_i == 1
        @existing_emails_to_destroy << ce
      else
        ce.email = params[:contact_email][ce.id.to_s][:email]
        ce.email_type = params[:contact_email][ce.id.to_s][:email_type]

        if new_email_is_primary
          ce.is_primary = false
        else
          ce.is_primary = ((params[:contact_email][:is_primary].to_i == ce.id) ? true : false)
        end

        if ! ce.valid?
          object.errors.add_to_base(ce.errors.collect{|attribute,msg| "#{attribute}  #{msg}"}.join('<br/>'))
          flash[:error] = (flash[:ceerror].blank? ? '' : flash[:ceerror]) + ce.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>')
        end
        existing_emails << ce
      end
    }
    deduped_emails << existing_emails
    deduped_emails.flatten!

    has_primary = false
    deduped_emails.collect{|ce| has_primary = ce.is_primary}
    unless has_primary
      unless deduped_emails.blank?
        deduped_emails.first.is_primary = true
      end
    end
    return deduped_emails
  end

  def deal_with_addresses(object)
    flash[:caerror] = nil
    number_new_addresses = params[:new_addresses]
    existing_addresses = params[:contact_address_ids]
    new_addresses = []
    existing_addresses = []
    @existing_addresses_to_destroy = []
    deduped_addresses = []

    #so we need to:
    # Delete existing addresses that've been checked as needing deletion
    # Add the new addresses, with some error checking.
    # Ensure that only one address is a primary, across both the new and old addresses.
    # I suspect this will be much easier in rails 2.3 because of the :autosave association attribute.
    #
    new_address_is_primary = nil

    number_new_addresses.each do |i|
      unless params[:new_address][i][:street1].blank?
        new_address = {
          :address_type => params[:new_address][i][:address_type],
          :street1 => params[:new_address][i][:street1],
          :street2 => params[:new_address][i][:street2],
          :city => params[:new_address][i][:city],
          :state => params[:new_address][i][:state],
          :zip => params[:new_address][i][:zip],
          :country => params[:new_address][i][:country],
          :is_primary => ((params[:new_address][:is_primary] == i) ? true : false),
          :contact => object
        }
        logger.warn(new_address.inspect + "\n")
        ca = ContactAddress.new(new_address)
        if ! ca.valid?
          object.errors.add_to_base(ca.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>'))
          flash[:caerror] = (flash[:caerror].blank? ? '' : flash[:caerror]) + ca.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>')
        else
          if ca.is_primary
            new_address_is_primary = true
          end
          deduped_addresses << ca
        end
      end
    end

    existing_address_is_primary = nil
    object.contact_addresses.each do |ca|
      if params[:contact_address][ca.id.to_s][:delete].to_i == 1
        @existing_addresses_to_destroy << ca
      else
        ca.street1 = params[:contact_address][ca.id.to_s][:street1]
        ca.street2 = params[:contact_address][ca.id.to_s][:street2]
        ca.city = params[:contact_address][ca.id.to_s][:city]
        ca.state = params[:contact_address][ca.id.to_s][:state]
        ca.zip = params[:contact_address][ca.id.to_s][:zip]
        ca.country = params[:contact_address][ca.id.to_s][:country]
        ca.address_type = params[:contact_address][ca.id.to_s][:address_type]

        if new_address_is_primary
          ca.is_primary = false
        else
          ca.is_primary = ((params[:contact_address][:is_primary].to_i == ca.id) ? true : false)
        end

        if ! ca.valid?
          object.errors.add_to_base(ca.errors.collect{|attribute,msg| "#{attribute}  #{msg}"}.join('<br/>'))
          flash[:error] = (flash[:caerror].blank? ? '' : flash[:caerror]) + ca.errors.collect{|attribute,msg| "#{attribute} #{msg}"}.join('<br/>')
        end
        existing_addresses << ca
      end
    end
    deduped_addresses << existing_addresses
    deduped_addresses.flatten!

    has_primary = false
    deduped_addresses.collect{|ca| has_primary = ca.is_primary}
    unless has_primary
      unless deduped_addresses.blank?
        deduped_addresses.first.is_primary = true
      end
    end
    return deduped_addresses
  end

  # This will auto-create tags that we haven't seen yet.
  def parse_tag_list(param)
    param[:tags_to_parse] ||= ''
    param[:tags_to_parse].split(',').each do |tag|
      matchval = tag.match(/\(id\:(\d+)\)$/)
      if matchval
        param[:tag_list] << matchval[1].to_i
      elsif param[:autocreate] && param[:autocreate] == true
        begin
          unless tag.blank?
            nt = Tag.create(:title => tag)
            param[:tag_list] << nt.id
          end
        rescue Exception => exc
          flash[:ceerror] = "There was an error creating that tag: #{exc.message}"
        end
      end
    end
  end

end
