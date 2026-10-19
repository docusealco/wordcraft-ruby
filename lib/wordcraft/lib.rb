# frozen_string_literal: true

require 'ffi'

module WordCraft
  module Lib
    extend FFI::Library

    PLATFORM =
      case FFI::Platform::OS
      when 'darwin'
        FFI::Platform::ARCH == 'aarch64' ? 'arm64-darwin' : 'x86_64-darwin'
      else
        arch = FFI::Platform::ARCH == 'aarch64' ? 'aarch64' : 'x86_64'

        is_musl = defined?(FFI::Platform::IS_GNU) ? !FFI::Platform::IS_GNU : RbConfig::CONFIG['host_os'].include?('musl')

        is_musl ? "#{arch}-linux-musl" : "#{arch}-linux"
      end

    LIB_FILE = FFI::Platform::OS == 'darwin' ? 'libwordcraft.dylib' : 'libwordcraft.so'

    PLATFORM_DIR = File.join(__dir__, PLATFORM)

    ffi_lib [ENV.fetch('WORDCRAFT_LIB', nil), File.join(PLATFORM_DIR, LIB_FILE), 'wordcraft'].compact

    MARKUP = 1

    RGBA = 0
    PNG = 1
    JPEG = 2

    class Buffer < FFI::Struct
      layout :data, :pointer,
             :len, :size_t,
             :cap, :size_t
    end

    attach_function :wc_open, %i[pointer size_t uint32 pointer pointer], :int32, blocking: true
    attach_function :wc_page_count, %i[pointer pointer pointer], :int32, blocking: true
    attach_function :wc_to_pdf, [:pointer, Buffer.by_ref, :pointer], :int32, blocking: true
    attach_function :wc_render,
                    [:pointer, :size_t, :float, :uint32, :uint8, Buffer.by_ref, :pointer, :pointer, :pointer],
                    :int32, blocking: true
    attach_function :wc_close, [:pointer], :void
    attach_function :wc_free_buffer, [Buffer.by_value], :void
    attach_function :wc_free_error, [:pointer], :void
    attach_function :wc_add_font, %i[pointer size_t], :int32, blocking: true
    attach_function :wc_load_system_fonts, [], :int64, blocking: true

    module_function

    def open_document(docx, markup: false)
      raise Error, 'empty document' if docx.nil? || docx.empty?

      input = FFI::MemoryPointer.new(:uint8, docx.bytesize)
      input.put_bytes(0, docx)
      out = FFI::MemoryPointer.new(:pointer)
      err = FFI::MemoryPointer.new(:pointer)

      code = wc_open(input, docx.bytesize, markup ? MARKUP : 0, out, err)

      raise Error, take_error(err.read_pointer, code) unless code.zero?

      FFI::AutoPointer.new(out.read_pointer, method(:wc_close))
    end

    def page_count(document)
      count = FFI::MemoryPointer.new(:size_t)
      err = FFI::MemoryPointer.new(:pointer)

      code = wc_page_count(document, count, err)

      raise Error, take_error(err.read_pointer, code) unless code.zero?

      count.read(:size_t)
    end

    def to_pdf(document)
      out = Buffer.new
      err = FFI::MemoryPointer.new(:pointer)

      code = wc_to_pdf(document, out, err)

      raise Error, take_error(err.read_pointer, code) unless code.zero?

      take_buffer(out)
    end

    def render(document, index, scale, format, quality)
      out = Buffer.new
      width = FFI::MemoryPointer.new(:uint32)
      height = FFI::MemoryPointer.new(:uint32)
      err = FFI::MemoryPointer.new(:pointer)

      code = wc_render(document, index, scale, format, quality, out, width, height, err)

      raise Error, take_error(err.read_pointer, code) unless code.zero?

      [take_buffer(out), width.read_uint32, height.read_uint32]
    end

    def add_font(bytes)
      raise Error, 'empty font' if bytes.nil? || bytes.empty?

      input = FFI::MemoryPointer.new(:uint8, bytes.bytesize)
      input.put_bytes(0, bytes)

      added = wc_add_font(input, bytes.bytesize)

      raise Error, 'could not add the font' if added.negative?

      added
    end

    def load_system_fonts
      count = wc_load_system_fonts

      raise Error, 'could not load the system fonts' if count.negative?

      count
    end

    def take_buffer(buffer)
      buffer[:data].read_bytes(buffer[:len])
    ensure
      wc_free_buffer(buffer)
    end

    def take_error(ptr, code)
      return "wordcraft error #{code}" if ptr.null?

      ptr.read_string.force_encoding(Encoding::UTF_8)
    ensure
      wc_free_error(ptr) unless ptr.null?
    end
  end
end
