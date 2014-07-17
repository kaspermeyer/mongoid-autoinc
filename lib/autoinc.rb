require 'autoinc/incrementor'

module Mongoid
  module Autoinc
    extend ActiveSupport::Concern

    AlreadyAssignedError = Class.new(StandardError)
    AutoIncrementsError = Class.new(StandardError)

    included { before_create(:update_auto_increments) }

    module ClassMethods
      # Returns all incrementing fields of the document
      #
      # @return [ Hash ] +Hash+ with fields and their autoincrement options
      def incrementing_fields
        if superclass.respond_to?(:incrementing_fields)
          @incrementing_fields ||= superclass.incrementing_fields.dup
        else
          @incrementing_fields ||= {}
        end
      end

      # Set an autoincrementing field for a +Mongoid::Document+
      #
      # @param [ Symbol ] field The name of the field to apply autoincrement to
      # @param [ Hash ] options The options to pass to that field
      def increments(field, options = {})
        incrementing_fields[field] = options.reverse_merge!(auto: true)
        attr_protected(field) if respond_to?(:attr_protected)
      end
    end

    # Manually assign the next number to the passed autoinc field.
    #
    # @return [ Fixnum ] The assigned number
    def assign!(field)
      options = self.class.incrementing_fields[field]
      fail AutoIncrementsError if options[:auto]
      fail AlreadyAssignedError if send(field).present?
      increment!(field, options)
    end

    # Sets autoincrement values for all autoincrement fields.
    #
    # @return [ true ]
    def update_auto_increments
      self.class.incrementing_fields.each do |field, options|
        increment!(field, options) if options[:auto]
      end && true
    end

    # Set autoincrement value for the passed autoincrement field,
    # using the passed options
    #
    # @param [ Symbol ] field Field to set the autoincrement value for.
    # @param [ Hash ] options Options to pass through to the serializer.
    #
    # @return [ true ] The value of `write_attribute`
    def increment!(field, options)
      options = options.dup
      model_name = (options.delete(:model_name) || self.class.model_name).to_s
      options[:scope] = evaluate_scope(options[:scope]) if options[:scope]
      options[:step] = evaluate_step(options[:step]) if options[:step]
      write_attribute(
          field.to_sym,
          Mongoid::Autoinc::Incrementor.new(model_name, field, options).inc
      )
    end

    # Asserts the validity of the passed scope
    #
    # @param [ Object ] scope The +Symbol+ or +Proc+ to evaluate
    #
    # @return [ Object ] The scope of the autoincrement call
    def evaluate_scope(scope)
      return send(scope) if scope.is_a? Symbol
      return instance_exec(&scope) if scope.is_a? Proc
      fail 'scope is not a Symbol or a Proc'
    end

    # Returns the number to add to the current increment
    #
    # @param [ Object ] step The +Integer+ to be returned
    # or +Proc+ to be evaluated
    #
    # @return [ Integer ] The number to add to the current increment
    def evaluate_step(step)
      return step if step.is_a? Integer
      return evaluate_step_proc(step) if step.is_a? Proc
      fail 'step is not an Integer or a Proc'
    end

    # Executes a proc and returns its +Integer+ value
    #
    # @param [ Proc ] step_proc The +Proc+ to call
    #
    # @return [ Integer ] The number to add to the current increment
    def evaluate_step_proc(step_proc)
      result = instance_exec(&step_proc)
      return result if result.is_a? Integer
      fail 'step Proc does not evaluate to an Integer'
    end
  end
end
