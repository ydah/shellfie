# frozen_string_literal: true

require_relative "errors"
require "yaml"

module Shellfie
  module YamlSafety
    MAX_DEPTH = 100
    MAX_NODES = 100_000

    module_function

    def read_file(path, max_bytes:, label: "Configuration")
      raise ParseError, "#{label} file not found: #{path}" unless File.file?(path)

      content = File.open(path, "rb") { |file| file.read(max_bytes + 1) }
      raise ParseError, "#{label} file is too large: #{path} (max #{max_bytes} bytes)" if content.bytesize > max_bytes

      content
    end

    def load_file(path, max_bytes:, label: "Configuration", symbolize_names: true)
      value = YAML.safe_load(
        read_file(path, max_bytes: max_bytes, label: label), symbolize_names: symbolize_names, aliases: true
      )
      validate_tree!(value)
    rescue Psych::Exception => e
      raise ParseError, "Invalid #{label.downcase} YAML syntax: #{e.message}"
    end

    def validate_tree!(value)
      active = {}
      nodes = 0
      stack = [[value, 0, false]]

      until stack.empty?
        node, depth, leaving = stack.pop
        next unless node.is_a?(Hash) || node.is_a?(Array)
        if leaving
          active.delete(node.object_id)
          next
        end

        raise ParseError, "YAML aliases must not contain cycles" if active[node.object_id]
        raise ParseError, "YAML nesting is too deep (max #{MAX_DEPTH})" if depth > MAX_DEPTH
        nodes += 1
        raise ParseError, "YAML structure is too large (max #{MAX_NODES} collections)" if nodes > MAX_NODES

        active[node.object_id] = true
        stack << [node, depth, true]
        children = node.is_a?(Hash) ? node.flat_map { |key, nested| [key, nested] } : node
        children.reverse_each { |child| stack << [child, depth + 1, false] }
      end

      value
    end
  end
end
