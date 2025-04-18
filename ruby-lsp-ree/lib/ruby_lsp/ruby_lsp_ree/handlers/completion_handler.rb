require_relative "../utils/ree_lsp_utils"
require_relative "../ree_object_finder"
require_relative 'const_additional_text_edits_creator'
require_relative 'method_additional_text_edits_creator'

module RubyLsp
  module Ree
    class CompletionHandler
      include Requests::Support::Common
      include RubyLsp::Ree::ReeLspUtils

      RECEIVER_OBJECT_TYPES = [:enum, :dao, :bean, :async_bean]
      CANDIDATES_LIMIT = 100

      def initialize(index, uri, node_context)
        @index = index
        @uri = uri
        @node_context = node_context
        @root_node = @node_context.instance_variable_get(:@nesting_nodes).first
        @finder = ReeObjectFinder.new(@index)
      end

      def get_ree_receiver(receiver_node)
        return if !receiver_node || !receiver_node.is_a?(Prism::CallNode)
      
        @finder.find_objects_by_types(receiver_node.name.to_s, RECEIVER_OBJECT_TYPES).first
      end

      def get_ree_object_methods_completions_items(ree_receiver, receiver_node, node)
        location = receiver_node.location

        case @finder.object_type(ree_receiver)
        when :enum
          get_enum_values_completion_items(ree_receiver, location)
        when :bean, :async_bean
          get_bean_methods_completion_items(ree_receiver, location)
        when :dao
          get_dao_filters_completion_items(ree_receiver, location)
        else
          []
        end
      end

      def get_bean_methods_completion_items(bean_obj, location)
        bean_node = RubyLsp::Ree::ParsedDocumentBuilder.build_from_uri(bean_obj.uri, :bean)
        
        range = Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
          end: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
        )

        bean_node.bean_methods.map do |bean_method|
          signature = bean_method.signatures.first

          label_details = Interface::CompletionItemLabelDetails.new(
            description: "method",
            detail: get_detail_string(signature)
          )

          Interface::CompletionItem.new(
            label: bean_method.name,
            label_details: label_details,
            filter_text: bean_method.name,
            text_edit: Interface::TextEdit.new(
              range:  range,
              new_text: get_method_string(bean_method.name, signature)
            ),
            kind: Constant::CompletionItemKind::METHOD,
            insert_text_format: Constant::InsertTextFormat::SNIPPET,
            data: {
              owner_name: "Object",
              guessed_type: false,
            }
          )
        end
      end

      def get_dao_filters_completion_items(dao_obj, location)
        dao_node = RubyLsp::Ree::ParsedDocumentBuilder.build_from_uri(dao_obj.uri, :dao)
        
        range = Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
          end: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
        )

        dao_node.filters.map do |filter|
          signature = filter.signatures.first

          label_details = Interface::CompletionItemLabelDetails.new(
            description: "filter",
            detail: get_detail_string(signature)
          )

          Interface::CompletionItem.new(
            label: filter.name,
            label_details: label_details,
            filter_text: filter.name,
            text_edit: Interface::TextEdit.new(
              range:  range,
              new_text: get_method_string(filter.name, signature)
            ),
            kind: Constant::CompletionItemKind::METHOD,
            insert_text_format: Constant::InsertTextFormat::SNIPPET,
            data: {
              owner_name: "Object",
              guessed_type: false,
            }
          )
        end
      end

      def get_enum_values_completion_items(enum_obj, location)
        enum_node = RubyLsp::Ree::ParsedDocumentBuilder.build_from_uri(enum_obj.uri, :enum)

        class_name = enum_node.full_class_name

        label_details = Interface::CompletionItemLabelDetails.new(
          description: "from: #{class_name}",
          detail: ''
        )

        range = Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
          end: Interface::Position.new(line: location.start_line - 1, character: location.end_column + 1),
        )

        enum_node.values.map do |val|
          Interface::CompletionItem.new(
            label: val.name,
            label_details: label_details,
            filter_text: val.name,
            text_edit: Interface::TextEdit.new(
              range:  range,
              new_text: val.name
            ),
            kind: Constant::CompletionItemKind::METHOD,
            data: {
              owner_name: "Object",
              guessed_type: false,
            }
          )
        end
      end

      def get_class_name_completion_items(node)
        node_name = node.name.to_s
        class_name_objects = @finder.search_class_objects(node_name)
        
        return [] if class_name_objects.size == 0

        parsed_doc = RubyLsp::Ree::ParsedDocumentBuilder.build_from_ast(@root_node, @uri)

        imported_consts = []
        not_imported_consts = []

        class_name_objects.take(CANDIDATES_LIMIT).each do |full_class_name|
          entries = @index[full_class_name]

          entries.each do |entry|
            class_name = full_class_name.split('::').last
            package_name = package_name_from_uri(entry.uri)
            file_name = File.basename(entry.uri.to_s)
            entry_comment = entry.comments && entry.comments.size > 0 ? " (#{entry.comments})" : ''

            matched_import = parsed_doc.find_import_for_package(class_name, package_name)

            if matched_import   
              label_details = Interface::CompletionItemLabelDetails.new(
                description: "imported from: :#{package_name}",
                detail: entry_comment
              )
              
              imported_consts << Interface::CompletionItem.new(
                label: class_name,
                label_details: label_details,
                filter_text: class_name,
                text_edit: Interface::TextEdit.new(
                  range:  range_from_location(node.location),
                  new_text: class_name,
                ),
                kind: Constant::CompletionItemKind::CLASS,
                additional_text_edits: []
              )
            else
              label_details = Interface::CompletionItemLabelDetails.new(
                description: "from: :#{package_name}",
                detail: entry_comment + " #{file_name}"
              )

              not_imported_consts << Interface::CompletionItem.new(
                label: class_name,
                label_details: label_details,
                filter_text: class_name,
                text_edit: Interface::TextEdit.new(
                  range:  range_from_location(node.location),
                  new_text: class_name,
                ),
                kind: Constant::CompletionItemKind::CLASS,
                additional_text_edits: ConstAdditionalTextEditsCreator.call(parsed_doc, class_name, package_name, entry)
              )
            end
          end
        end

        imported_consts + not_imported_consts
      end

      def get_ree_objects_completions_items(node)
        ree_objects = @finder.search_objects(node.name.to_s, CANDIDATES_LIMIT)

        return [] if ree_objects.size == 0
  
        parsed_doc = RubyLsp::Ree::ParsedDocumentBuilder.build_from_ast(@root_node, @uri)

        ree_objects.map do |ree_object|
          ree_object_name = ree_object.name
          package_name = package_name_from_uri(ree_object.uri)
          signature = ree_object.signatures.first
          ree_type = get_ree_type(ree_object)

          label_details = Interface::CompletionItemLabelDetails.new(
            description: "#{ree_type}, from: :#{package_name}",
            detail: get_detail_string(signature)
          )

          Interface::CompletionItem.new(
            label: ree_object_name,
            label_details: label_details,
            filter_text: ree_object_name,
            text_edit: Interface::TextEdit.new(
              range:  range_from_location(node.location),
              new_text: get_method_string(ree_object_name, signature)
            ),
            kind: Constant::CompletionItemKind::METHOD,
            insert_text_format: Constant::InsertTextFormat::SNIPPET,
            data: {
              owner_name: "Object",
              guessed_type: false,
            },
            additional_text_edits: MethodAdditionalTextEditsCreator.call(parsed_doc, ree_object_name, package_name)
          )
        end
      end

      def get_detail_string(signature)
        return '' unless signature

        "(#{get_parameters_string(signature)})"
      end

      def get_parameters_string(signature)
        return '' unless signature

        signature.parameters.map(&:decorated_name).join(', ')
      end

      def get_method_string(fn_name, signature)
        return fn_name unless signature
        
        "#{fn_name}(#{get_parameters_placeholder(signature)})"
      end

      def get_parameters_placeholder(signature)
        return '' unless signature

        signature.parameters.to_enum.with_index.map do |signature_param, index|
          case signature_param          
          when RubyIndexer::Entry::KeywordParameter, RubyIndexer::Entry::OptionalKeywordParameter
            "#{signature_param.name}: ${#{index+1}:#{signature_param.name}}"
          else
            "${#{index+1}:#{signature_param.name}}"
          end
        end.join(', ')
      end
    end
  end
end