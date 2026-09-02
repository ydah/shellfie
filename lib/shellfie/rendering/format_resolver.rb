# frozen_string_literal: true

module Shellfie
  class FormatResolver
    class << self
      def resolve(output_path, explicit:, default:)
        return explicit if explicit
        return default if output_path == "-"

        extension = File.extname(output_path).delete_prefix(".")
        extension.empty? ? default : extension
      end
    end
  end
end
