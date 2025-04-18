module RubyLsp
  module Ree
    class ReeSourceEditor
      include RubyLsp::Ree::ReeLspUtils

      attr_reader :source_lines

      def initialize(source)
        @source_lines = source.lines
      end

      def source
        @source_lines.join
      end

      def contains_link_usage?(link_node)
        source_lines_except_link = source_lines[0...(link_node.location.start_line-1)] + source_lines[(link_node.location.end_line)..-1]
        source_lines_except_link.any?{ |source_line| source_line.match?(/\W#{link_node.name}\W/)}
      end

      def contains_link_import_usage?(link_node, link_import)
        source_lines_except_link = source_lines[0...(link_node.location.start_line-1)] + source_lines[(link_node.location.end_line)..-1]
        source_lines_except_link.any?{ |source_line| source_line.match?(/\W#{link_import}\W/)}
      end

      def remove_link(link_node)
        set_empty_lines!(link_node.location.start_line-1, link_node.location.end_line-1)
      end

      def remove_link_import(link_node, link_import)
        imports_str = link_node.imports.reject{ _1 == link_import}.join(' & ')

        block_start_col = link_node.import_block_open_location.start_column
        block_line = link_node.import_block_open_location.start_line-1
        block_end_line = link_node.import_block_close_location.end_line-1

        source_lines[block_line] = source_lines[block_line][0..block_start_col] + " #{imports_str} }\n"
        set_empty_lines!(block_line+1, block_end_line)
      end

      def remove_link_import_arg(link_node)
        link_line = link_node.location.start_line - 1
        link_end_line = link_node.location.end_line - 1
        link_name_end = link_node.first_arg_location.end_column - 1

        source_lines[link_line] = source_lines[link_line][0..link_name_end] + "\n"
        set_empty_lines!(link_line+1, link_end_line)
      end

      def remove_link_block(links_container_node, links_container_block_node)
        return source_lines unless links_container_block_node
        
        link_container_start_line = links_container_node.location.start_line-1
        link_container_end_line = links_container_node.location.end_line-1
        block_start = links_container_block_node.location.start_column-1

        source_lines[link_container_start_line] = source_lines[link_container_start_line][0..block_start] + "\n"
        set_empty_lines!(link_container_start_line+1, link_container_end_line)
      end

      def set_empty_lines!(start_line, end_line)
        (start_line .. end_line).each do |i|
          source_lines[i] = ''
        end
      end
    end
  end
end