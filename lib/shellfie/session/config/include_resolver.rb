# frozen_string_literal: true

module Shellfie
  module Session
    class Config
      class IncludeResolver
        def self.call(path)
          new(path).resolve(path)
        end

        def initialize(path)
          @root = File.dirname(path)
          @files = 0
          @bytes = 0
        end

        def resolve(path, stack: [], policy: nil)
          validate_chain(path, stack)
          content = read_session(path)
          raw = parse_session(content, path)
          own_provenance = provenance_for(raw, path)
          return [raw, [[path, content]], own_provenance] unless raw[:include]

          policy = include_policy(raw, policy)
          merged, documents, provenance = resolve_nested(raw[:include], path, stack: stack, policy: policy)
          documents.unshift([path, content])
          own = raw.except(:include, :include_policy)
          own_provenance.reject! { |key, _value| %i[include include_policy].include?(key.first) }
          merged, provenance = merge(merged, own, provenance, own_provenance)
          [merged, documents, provenance]
        rescue Errno::ENOENT
          raise ParseError, "Included session file not found from #{path}"
        end

        private

        def validate_chain(path, stack)
          return unless stack.include?(path)

          chain = (stack + [path]).map { |item| File.basename(item) }.join(' -> ')
          raise ParseError, "Circular session include: #{chain}"
        end

        def read_session(path)
          content = YAMLSafety.read_file(path, max_bytes: Config::MAX_BYTES, label: 'Session')
          @files += 1
          @bytes += content.bytesize
          raise ParseError, "Too many session includes (max #{Config::MAX_INCLUDE_FILES})" if @files > Config::MAX_INCLUDE_FILES
          raise ParseError,
                "Included sessions are too large in total (max #{Config::MAX_TOTAL_BYTES} bytes)" if @bytes > Config::MAX_TOTAL_BYTES

          content
        end

        def parse_session(content, path)
          raw = YAML.safe_load(content, symbolize_names: true, aliases: true)
          YAMLSafety.validate_tree(raw)
          raise ParseError, "Included session must be a YAML mapping: #{path}" unless raw.is_a?(Hash)

          raw
        end

        def include_policy(raw, inherited)
          declared = raw[:include_policy]
          raise ParseError, 'include_policy must be allow or root' if raw.key?(:include_policy) && !%w[allow
                                                                                                       root].include?(declared)
          return 'root' if inherited == 'root' || declared == 'root'

          declared || inherited || 'allow'
        end

        def resolve_nested(includes, path, stack:, policy:)
          merged = {}
          provenance = {}
          documents = []
          Array(includes).each do |included|
            included_path = resolve_path(included, path, policy)
            value, nested_documents, nested_provenance = resolve(included_path, stack: stack + [path], policy: policy)
            merged, provenance = merge(merged, value, provenance, nested_provenance)
            documents.concat(nested_documents)
          end
          [merged, documents, provenance]
        end

        def resolve_path(included, path, policy)
          raise ParseError, 'Included session path must be a string' unless included.is_a?(String)

          resolved = File.realpath(File.expand_path(included, File.dirname(path)))
          if policy == 'root' && resolved != @root && !resolved.start_with?("#{@root}#{File::SEPARATOR}")
            raise ParseError, "Included session escapes the session root: #{included}"
          end

          resolved
        end

        def merge(base, overrides, base_provenance = {}, override_provenance = {}, prefix = [])
          merged = base.dup
          provenance = base_provenance.dup
          overrides.each do |key, right|
            target = prefix + [key]
            if %i[steps requires outputs redact].include?(key)
              offset = Array(base[key]).size
              merged[key] = Array(base[key]) + Array(right)
              copy_provenance(provenance, override_provenance, target) do |path|
                path.size > target.size && path[target.size].is_a?(Integer) ? target + [path[target.size] + offset] + path[(target.size + 1)..] : path
              end
            elsif base[key].is_a?(Hash) && right.is_a?(Hash)
              merged[key], provenance = merge(base[key], right, provenance, override_provenance, target)
            else
              merged[key] = right
              provenance.delete_if { |path, _value| path[0, target.size] == target }
              copy_provenance(provenance, override_provenance, target)
            end
          end
          [merged, provenance]
        end

        def provenance_for(value, source, path = [], result = {})
          result[path] = [source, path]
          case value
          when Hash then value.each { |key, nested| provenance_for(nested, source, path + [key], result) }
          when Array then value.each_with_index { |nested, index|
            provenance_for(nested, source, path + [index], result)
          }
          end
          result
        end

        def copy_provenance(target_map, source_map, prefix)
          source_map.each do |path, source|
            next unless path[0, prefix.size] == prefix

            target_map[block_given? ? yield(path) : path] = source
          end
        end
      end
    end
  end
end
