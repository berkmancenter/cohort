class FreemailerCampaign < ActiveRecord::Base
  belongs_to :sender, :class_name => 'User'
  has_many :freemailer_campaign_contacts, :dependent => :destroy
  has_many :contacts, :through => :freemailer_campaign_contacts

  validates_uniqueness_of :title, :scope => :sender_id, :on => :create, :message => "must be unique" #JS me

  before_destroy :remove_active_campaign

  def contact_names
    contacts.map(&:name_for_display).join(', ').squeeze(' ')
  end

  def contact_emails
    self[:contacts].map(&:primary_email)
  end

  def status
    if sent
      'Sent'
    else
      'Unsent'
    end
  end

  def make_active_for_sender
    sender.active_campaign = self
    sender.save
  end

  def preview
    fill_template(preview_user)
  end

  def send_campaign
    if not self[:sent]
      freemailer_campaign_contacts.each do |contact_join|
        self.send_later(:send_individual_mail,contact_join)
      end
      self[:sent] = true; self.save
    end
  end

  def send_individual_mail(contact_join)
    begin
      if contact_join.delivery_status !~ /Success/
        raise Net::SMTPFatalError if rand[2] == 1
        Freemailer.deliver_from_template(self,contact_join.contact)
        contact_join.delivery_status = "Successful"
        contact_join.save
      end
    rescue Net::SMTPError => e
      puts "Delivery error rescued!"
      debugger
      contact_join.delivery_status = e.to_s
      contact_join.save
    end
  end
  
  def preview_user
    {
      'first name' => 'John',
      'last name' => 'Doe',
      'middle name' => 'H',
      'name' => 'John Doe',
      'email' => 'john@doe.com',
      'address' => "123 Some Pl.\nWhere, Ever  90210\nCanada"
    }
  end

  def fill_template_for_contact(person)
    fill_template ({
      'first name' => person.first_name,
      'last name' => person.last_name,
      'middle name' => person.middle_name,
      'middle initial' => (person.middle_name or '').first.upcase,
      'name' => person.name_for_display,
      'email' => person.primary_email,
      'address' => person.primary_address
    })
  end

  def fill_template(user_hash)
    user_hash.default = ''
    (body_template ||  "-- Body is empty -- ").gsub(/\[\[(.*?)\]\]/) do |item|
      user_hash[$1].to_s
    end
  end
  
  def successfully_sent
    freemailer_campaign_contacts.count( :conditions => { :delivery_status => "Successful" })
  end

  def remove_active_campaign
    if sender.active_campaign == self
      sender.active_campaign = nil
      sender.save
    end
  end
end
