# frozen_string_literal: true

module WordCraft
  autoload :Document, 'wordcraft/document'
  autoload :Lib, 'wordcraft/lib'
  autoload :VERSION, 'wordcraft/version'
  autoload :WORDCRAFT_REV, 'wordcraft/version'

  class Error < StandardError
  end

  module_function

  def open(path, markup: false, &)
    raise ArgumentError, 'expected a file path, got bytes; use WordCraft.open_buffer' if path.to_s.include?("\0")

    open_buffer(File.binread(path), markup:, &)
  end

  def open_buffer(input, markup: false)
    document = Document.new(input, markup:)

    return document unless block_given?

    begin
      yield document
    ensure
      document.close
    end
  end

  def add_font(bytes)
    Lib.add_font(bytes)
  end

  def add_font_file(path)
    add_font(File.binread(path))
  end

  def load_system_fonts
    Lib.load_system_fonts
  end
end
