module AASM
  module Persistence
    
    # Checks to see this class or any of it's superclasses inherit from
    # ActiveRecord::Base and if so includes ActiveRecordPersistence
    def self.set_persistence(base)
      # Use a fancier auto-loading thingy, perhaps.  When there are more persistence engines.
      hierarchy = base.ancestors.map {|klass| klass.to_s}
      
      if hierarchy.include?("ActiveRecord::Base")
        require File.join(File.dirname(__FILE__), 'persistence', 'active_record_persistence')
        base.send(:include, AASM::Persistence::ActiveRecordPersistence)
      elsif hierarchy.include?("CouchRest::ExtendedDocument")
        require File.join(File.dirname(__FILE__), 'persistence', 'couchrest_persistence')
        base.send(:include, AASM::Persistence::CouchRestPersistence)
      end
    end
  end
end
