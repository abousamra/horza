module Horza
  module Adapters
    class ActiveRecord < AbstractAdapter
      INVALID_ANCESTRY_MSG = 'Invalid relation. Ensure that the plurality of your associations is correct.'

      class << self
        def context_for_entity(entity)
          entity_context_map[entity]
        end

        def entity_context_map
          @map ||= ::Horza.descendants_map(::ActiveRecord::Base)
        end
      end

      def get!(id)
        entity_class(@context.find(id).attributes)
      rescue ::ActiveRecord::RecordNotFound => e
        raise Horza::Errors::RecordNotFound.new(e)
      end

      def find_first!(options = {})
        entity_class(base_query(options).first!.attributes)
      rescue ::ActiveRecord::RecordNotFound => e
        raise Horza::Errors::RecordNotFound.new(e)
      end

      def find_all(options = {})
        entity_class(base_query(options))
      end

      def create!(options = {})
        record = @context.new(options)
        record.save!
        entity_class(record.attributes)
      rescue ::ActiveRecord::RecordInvalid => e
        raise Horza::Errors::RecordInvalid.new(e)
      end

      def update!(id, options = {})
        record = @context.find(id)
        record.assign_attributes(options)
        record.save!
        record
      rescue ::ActiveRecord::RecordNotFound => e
        raise Horza::Errors::RecordNotFound.new(e)
      rescue ::ActiveRecord::RecordInvalid => e
        raise Horza::Errors::RecordInvalid.new(e)
      end

      def delete!(id)
        record = @context.find(id)
        record.destroy!
        true
      rescue ::ActiveRecord::RecordNotFound => e
        raise Horza::Errors::RecordNotFound.new(e)
      end

      def ancestors(options = {})
        result = walk_family_tree(@context.find(options[:id]), options)

        return nil unless result

        collection?(result) ? entity_class(result) : entity_class(result.attributes)
      end

      def to_hash
        raise ::Horza::Errors::CannotGetHashFromCollection.new if collection?
        raise ::Horza::Errors::QueryNotYetPerformed.new unless @context.respond_to?(:attributes)
        @context.attributes
      end

      private

      def base_query(options)
        @context.where(options).order('ID DESC')
      end

      def collection?(subject = @context)
        subject.is_a?(::ActiveRecord::Relation) || subject.is_a?(Array)
      end

      def walk_family_tree(object, options)
        via = options[:via] || []
        via.push(options[:target]).reduce(object) do |object, relation|
          raise ::Horza::Errors::InvalidAncestry.new(INVALID_ANCESTRY_MSG) unless object.respond_to? relation
          object.send(relation)
        end
      end
    end
  end
end
