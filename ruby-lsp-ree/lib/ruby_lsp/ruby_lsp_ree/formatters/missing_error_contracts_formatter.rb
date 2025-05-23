require_relative 'base_formatter'

module RubyLsp
  module Ree
    class MissingErrorContractsFormatter < BaseFormatter
      def call(source, _uri)
        parsed_doc = RubyLsp::Ree::ParsedDocumentBuilder.build_from_source(source)
        return source if !parsed_doc || !parsed_doc.has_root_class?

        parsed_doc.parse_error_definitions
        parsed_doc.parse_instance_methods

        parsed_doc.doc_instance_methods.select(&:has_contract?).each do |doc_instance_method|
          doc_instance_method.parse_nested_local_methods(parsed_doc.doc_instance_methods)

          raised_errors = doc_instance_method.raised_errors_nested
          throws_errors = doc_instance_method.throws_errors

          missed_errors = raised_errors - throws_errors
          source = add_missed_errors(source, doc_instance_method, missed_errors)
        end

        source
      end

      private

      def add_missed_errors(source, doc_instance_method, missed_errors)
        return source if missed_errors.size == 0

        source_lines = source.lines

        if doc_instance_method.has_throw_section?
          position = doc_instance_method.throw_arguments_end_position
          line = doc_instance_method.throw_arguments_end_line

          if source_lines[line].strip.end_with?(")")
            source_lines[line] = source_lines[line][0..position] + ", #{missed_errors.join(', ')})\n"
          else
            source_lines[line] = source_lines[line][0..position] + ", #{missed_errors.join(', ')}\n"
          end
        else
          if doc_instance_method.contract_in_parentheses?
            position = doc_instance_method.contract_node_end_position
            line = doc_instance_method.contract_node_end_line

            source_lines[line] = source_lines[line][0..position] + ".throws(#{missed_errors.join(', ')})\n"
          else
            contract_end_position = doc_instance_method.contract_node_contract_end_position
            start_line = doc_instance_method.contract_node_start_line
            end_line = doc_instance_method.contract_node_end_line

            source_lines[start_line] = source_lines[start_line][0..contract_end_position] + "(" + source_lines[start_line][contract_end_position+1..-1].lstrip
            source_lines[end_line] = source_lines[end_line].chomp + ").throws(#{missed_errors.join(', ')})\n"
          end
        end

        source_lines.join
      end
    end
  end
end