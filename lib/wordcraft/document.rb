# frozen_string_literal: true

module WordCraft
  class Document
    DEFAULT_DPI = 144

    def initialize(input, markup: false)
      @pointer = Lib.open_document(read_input(input), markup:)
    end

    def page_count
      @page_count ||= Lib.page_count(pointer)
    end

    def to_pdf
      Lib.to_pdf(pointer)
    end

    def to_png(page:, dpi: DEFAULT_DPI)
      render(page, dpi, Lib::PNG).first
    end

    def to_jpeg(page:, dpi: DEFAULT_DPI, quality: 85)
      unless quality.is_a?(Integer) && quality.between?(1, 100)
        raise ArgumentError, "quality must be between 1 and 100, got #{quality.inspect}"
      end

      render(page, dpi, Lib::JPEG, quality).first
    end

    def to_rgba(page:, dpi: DEFAULT_DPI)
      render(page, dpi, Lib::RGBA)
    end

    def close
      @pointer&.free
      @pointer = nil
    end

    def closed?
      @pointer.nil?
    end

    private

    def pointer
      @pointer || raise(Error, 'document is closed')
    end

    def read_input(input)
      if input.respond_to?(:read)
        bytes = input.read
        input.rewind if input.respond_to?(:rewind)

        return bytes
      end

      raise ArgumentError, "expected an IO or a String of bytes, got #{input.class}" unless input.is_a?(String)

      input
    end

    def render(page, dpi, format, quality = 0)
      unless dpi.is_a?(Numeric) && dpi.positive? && dpi.finite?
        raise ArgumentError, "dpi must be a positive number, got #{dpi.inspect}"
      end

      count = page_count

      unless page.is_a?(Integer) && page.between?(1, count)
        raise ArgumentError, "page must be between 1 and #{count}, got #{page.inspect}"
      end

      Lib.render(pointer, page - 1, dpi / 72.0, format, quality)
    end
  end
end
