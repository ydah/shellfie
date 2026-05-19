# frozen_string_literal: true

require "fileutils"
require "tempfile"
require "tmpdir"

module Shellfie
  class OutputWriter
    class << self
      def write(path, extension:)
        FileUtils.mkdir_p(output_directory(path)) unless stdout?(path)
        temp = Tempfile.new(["shellfie", ".#{extension}"], output_directory(path), binmode: true)
        temp.close
        yield temp.path

        return File.binread(temp.path) if stdout?(path)

        FileUtils.mv(temp.path, path)
        path
      ensure
        if temp
          temp.close unless temp.closed?
          File.delete(temp.path) if File.exist?(temp.path)
        end
      end

      private

      def stdout?(path)
        path == "-"
      end

      def output_directory(path)
        return Dir.tmpdir if stdout?(path)

        directory = File.dirname(path)
        directory == "." ? Dir.pwd : directory
      end
    end
  end
end
