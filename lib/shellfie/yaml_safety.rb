# frozen_string_literal: true

require_relative "errors"
require "yaml"

module Shellfie
  module YamlSafety
    MAX_DEPTH = 100
    MAX_NODES = 100_000

    module_function

    def annotate_validation_error(error, documents, provenance: {})
      if (target = validation_path(error.message)) && (origin = provenance[target])
        path, local_path = origin
        content = documents.assoc(path)&.last
        if content && (location = location_for_path(content, local_path))
          return error.class.new("#{path}:#{location[0]}:#{location[1]}: #{error.message}")
        end
      end

      documents.each do |path, content|
        next unless path && content

        location = validation_location(content, error.message)
        return error.class.new("#{path}:#{location[0]}:#{location[1]}: #{error.message}") if location
      end

      path = documents.first&.first
      error.class.new(path ? "#{path}: #{error.message}" : error.message)
    end

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

    def validation_location(content, message)
      locations = {}
      collect_locations(Psych.parse(content).root, [], locations)
      target = validation_path(message)
      return locations[target] if target && locations[target]

      locations.sort_by { |path, _location| -path.size }.each do |path, location|
        return location if message.include?(format_path(path))
      end
      nil
    rescue Psych::Exception
      nil
    end

    def location_for_path(content, path)
      locations = {}
      collect_locations(Psych.parse(content).root, [], locations)
      locations[path] || locations[path[0...-1]]
    rescue Psych::Exception
      nil
    end

    def collect_locations(node, path, locations)
      case node
      when Psych::Nodes::Mapping
        node.children.each_slice(2) do |key, value|
          next unless key.respond_to?(:value)

          child_path = path + [key.value.to_sym]
          locations[child_path] = [key.start_line + 1, key.start_column + 1]
          collect_locations(value, child_path, locations)
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| collect_locations(child, path + [index], locations) }
      end
    end

    def validation_path(message)
      if (match = /Unknown (.+?) key\(s\):\s*([^,\s]+)/.match(message))
        prefix = match[1] == "configuration" ? [] : parse_path(match[1])
        return prefix + [match[2].to_sym]
      end

      explicit = message[/\b(?:steps|outputs|frames|lines)\[\d+\](?:\.[a-z_]+)*|\b(?:terminal|render|window|font|animation|cursor|limits)\.[a-z_]+/]
      return parse_path(explicit) if explicit

      {
        "Session config version" => [:version], "mode must" => [:mode], "Invalid theme" => [:theme],
        "redaction" => [:redact], "requires" => [:requires], "terminal.env" => %i[terminal env],
        "title must" => [:title], "headless must" => [:headless]
      }.each { |fragment, path| return path if message.include?(fragment) }
      nil
    end

    def parse_path(value)
      value.to_s.scan(/[A-Za-z_][A-Za-z0-9_]*|\d+/).map { |part| part.match?(/\A\d+\z/) ? part.to_i : part.to_sym }
    end

    def format_path(path)
      path.each_with_object(+"") do |part, result|
        if part.is_a?(Integer)
          result << "[#{part}]"
        else
          result << "." unless result.empty?
          result << part.to_s
        end
      end
    end
  end
end
