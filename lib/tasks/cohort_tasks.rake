## desc "Explaining what the task does"
#
# task :fckeditor do
#   # Task goes here
# end

namespace :cohort do
  def setup 
    require 'fastercsv'
  end
  
  desc 'Import sample data'
  task (:import => :environment) do
    setup
    columns = Contact.columns.collect{|c| c.name}
    columns.delete('id')

    import_tag = Tag.create(:title => 'Auto import')
    u = User.get_import_user

    FasterCSV.foreach("tmp/import.csv", {:headers => true,:header_converters => :symbol}) do |row|
      c = Contact.new
      rhash = row.to_hash
      columns.each do |col|
        c[col.to_sym] = rhash[col.to_sym]
      end

      [:notes,:notes_2,:notes_3,:notes_4].each do |col|
        if rhash[col] && ! rhash[col].strip.blank?
          c.notes << Note.new(:contact => c, :note => rhash[col], :user => u)
        end
      end

      [:email,:email_2,:email_3,:email_4].each do |col|
        if rhash[col] && ! rhash[col].strip.blank?
          ce = ContactEmail.new(:email => rhash[col].strip, :email_type => 'unknown', :is_primary => ((col == :email) ? true : false ))
          if ! ce.valid?
            puts "Invalid email address: #{ce.errors.full_messages.join(' ')}"
          else
            c.contact_emails << ce
          end
        end
      end

      ['1','2','3','4'].each do |ad|
        test_col = "address_#{ad}_street1"
        if rhash[test_col.to_sym] && ! rhash[test_col.to_sym].blank?
          ca = ContactAddress.new
          ['street1','street2','city','state','zip','country'].each do |col|
            ca[col] = rhash["address_#{ad}_#{col}".to_sym]
          end
          ca.is_primary = (ad == '1') ? true : false
          ca.address_type = (ad == '1') ? 'work' : 'unknown'
          if ! ca.valid?
            puts "Invalid contact address: #{ca.errors.full_messages.join(' ')}"
          else
            c.contact_addresses << ca
          end
        end
      end

      if c.valid?
        c.save
        c.tags << import_tag
        c.save
      else
        puts 'Invalid contact: NOT ADDED! ' + c.errors.full_messages.join(' ') 
      end
    end
    Contact.rebuild_index
    Note.rebuild_index
  end
  
end

