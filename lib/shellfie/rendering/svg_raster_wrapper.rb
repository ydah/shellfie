# frozen_string_literal: true

require 'tempfile'
require 'mini_magick'

module Shellfie
  class SvgRasterWrapper
    class << self
      def write(output_path)
        temp = Tempfile.new(['shellfie-svg', '.png'], binmode: true)
        temp.close
        yield temp.path
        image = MiniMagick::Image.open(temp.path)
        File.binwrite(output_path, svg_document(image.width, image.height, File.binread(temp.path)))
      ensure
        if temp
          temp.close unless temp.closed?
          FileUtils.rm_f(temp.path)
        end
      end

      private

      def svg_document(width, height, png_data)
        encoded = [png_data].pack('m0')
        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
            <image width="#{width}" height="#{height}" href="data:image/png;base64,#{encoded}"/>
          </svg>
        SVG
      end
    end
  end
end
