# frozen_string_literal: true

module WordCraft
  autoload :Lib, 'wordcraft/lib'
  autoload :VERSION, 'wordcraft/version'
  autoload :WORDCRAFT_REV, 'wordcraft/version'

  class Error < StandardError
  end

  module_function

  def convert(docx, markup: false)
    Lib.convert(docx, markup:)
  end

  def convert_file(input_path, output_path, markup: false)
    File.binwrite(output_path, convert(File.binread(input_path), markup:))

    output_path
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
