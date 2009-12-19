module AASM
  module Persistence
    module CouchRestPersistence
      # This method:
      #
      # * extends the model with ClassMethods
      # * includes InstanceMethods
      #
      # Unless the corresponding methods are already defined, it includes
      # * ReadState
      # * WriteState
      # * WriteStateWithoutPersistence
      #
      # Adds
      #
      #   before_validation_on_create :aasm_ensure_initial_state
      #
      # As a result, it doesn't matter when you define your methods - the following 2 are equivalent
      #
      #   class Foo < CouchRest::Base
      #     def aasm_write_state(state)
      #       "bar"
      #     end
      #     include AASM
      #   end
      #
      #   class Foo < CouchRest::Base
      #     include AASM
      #     def aasm_write_state(state)
      #       "bar"
      #     end
      #   end
      #
      def self.included(base)
        base.extend AASM::Persistence::CouchRestPersistence::ClassMethods
        base.send(:include, AASM::Persistence::CouchRestPersistence::InstanceMethods)
        base.send(:include, AASM::Persistence::CouchRestPersistence::ReadState) unless base.method_defined?(:aasm_read_state)
        base.send(:include, AASM::Persistence::CouchRestPersistence::WriteState) unless base.method_defined?(:aasm_write_state)
        base.send(:include, AASM::Persistence::CouchRestPersistence::WriteStateWithoutPersistence) unless base.method_defined?(:aasm_write_state_without_persistence)
        
        # should be a before_validation, but CouchRest doesn't yet support that
        base.set_callback :save, :before, :aasm_ensure_initial_state
      end

      module ClassMethods
        # Maps to the aasm_property in the database.  Deafults to "aasm_state".  You can write:
        #
        #   create_table :foos do |t|
        #     t.string :name
        #     t.string :aasm_state
        #   end
        #
        #   class Foo < CouchRest::Base
        #     include AASM
        #   end
        #
        # OR:
        #
        #   create_table :foos do |t|
        #     t.string :name
        #     t.string :status
        #   end
        #
        #   class Foo < CouchRest::Base
        #     include AASM
        #     aasm_property :status
        #   end
        #
        # This method is both a getter and a setter
        def aasm_property(property_name=nil)
          if property_name
            AASM::StateMachine[self].config.property = property_name.to_sym
            # @aasm_property = property_name.to_sym
          else
            AASM::StateMachine[self].config.property ||= :aasm_state
            # @aasm_property ||= :aasm_state
          end
          # @aasm_property
          AASM::StateMachine[self].config.property
        end
      end

      module InstanceMethods

        # Returns the current aasm_state of the object.  Respects reload and
        # any changes made to the aasm_state field directly
        #
        # Internally just calls <tt>aasm_read_state</tt>
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :pending
        #   foo.aasm_state = "opened"
        #   foo.aasm_current_state # => :opened
        #   foo.close # => calls aasm_write_state_without_persistence
        #   foo.aasm_current_state # => :closed
        #   foo.reload
        #   foo.aasm_current_state # => :pending
        #
        def aasm_current_state
          @current_state = aasm_read_state
        end

        private

        # Ensures that if the aasm_state property is nil and the record is new
        # that the initial state gets populated before validation on create
        #
        #   foo = Foo.new
        #   foo.aasm_state # => nil
        #   foo.valid?
        #   foo.aasm_state # => "open" (where :open is the initial state)
        #
        #
        #   foo = Foo.find(:first)
        #   foo.aasm_state # => 1
        #   foo.aasm_state = nil
        #   foo.valid?
        #   foo.aasm_state # => nil
        #
        def aasm_ensure_initial_state
          send("#{self.class.aasm_property}=", self.aasm_current_state.to_s)
        end

      end

      module WriteStateWithoutPersistence
        # Writes <tt>state</tt> to the state property, but does not persist it to the database
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :opened
        #   foo.close
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :opened
        #   foo.save
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :closed
        #
        # NOTE: intended to be called from an event
        def aasm_write_state_without_persistence(state)
          properties_by_name[self.class.aasm_property] = state.to_s
        end
      end

      module WriteState
        # Writes <tt>state</tt> to the state property and persists it to the database
        # using update_attribute (which bypasses validation)
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :opened
        #   foo.close!
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :closed
        #
        # NOTE: intended to be called from an event
        def aasm_write_state(state)
          old_value = properties_by_name[self.class.aasm_property]
          self[self.class.aasm_property] = state.to_s
          unless self.save
            self[self.class.aasm_property] = old_value
            return false
          end

          true
        end
      end

      module ReadState

        # Returns the value of the aasm_property - called from <tt>aasm_current_state</tt>
        #
        # If it's a new record, and the aasm state property is blank it returns the initial state:
        #
        #   class Foo < CouchRest::Base
        #     include AASM
        #     aasm_property :status
        #     aasm_state :opened
        #     aasm_state :closed
        #   end
        #
        #   foo = Foo.new
        #   foo.current_state # => :opened
        #   foo.close
        #   foo.current_state # => :closed
        #
        #   foo = Foo.find(1)
        #   foo.current_state # => :opened
        #   foo.aasm_state = nil
        #   foo.current_state # => nil
        #
        # NOTE: intended to be called from an event
        #
        # This allows for nil aasm states - be sure to add validation to your model
        def aasm_read_state
          if new_record?
            send(self.class.aasm_property).blank? ? self.class.aasm_initial_state : send(self.class.aasm_property).to_sym
          else
            send(self.class.aasm_property).nil? ? nil : send(self.class.aasm_property).to_sym
          end
        end
      end
    end
  end
end