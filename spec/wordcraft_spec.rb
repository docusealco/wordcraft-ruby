# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe WordCraft do
  let(:docx) { build_docx('Hello from Ruby', 'Second paragraph') }

  describe '.open' do
    it 'opens a file path' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'in.docx')
        File.binwrite(path, docx)

        expect(described_class.open(path, &:page_count)).to eq(1)
        expect(described_class.open(path, markup: true, &:to_pdf)).to start_with('%PDF-')
      end
    end

    it 'returns an open document without a block' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'in.docx')
        File.binwrite(path, docx)
        document = described_class.open(path)

        expect(document).not_to be_closed

        document.close
      end
    end

    it 'raises ArgumentError for DOCX bytes' do
      expect { described_class.open(docx) }.to raise_error(ArgumentError, /open_buffer/)
    end

    it 'raises Errno::ENOENT for a missing file' do
      expect { described_class.open('missing.docx') }.to raise_error(Errno::ENOENT)
    end
  end

  describe '.open_buffer' do
    it 'opens a String of bytes' do
      expect(described_class.open_buffer(docx, &:page_count)).to eq(1)
    end

    it 'opens a StringIO' do
      expect(described_class.open_buffer(StringIO.new(docx), &:page_count)).to eq(1)
    end

    it 'opens a File' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'in.docx')
        File.binwrite(path, docx)

        expect(File.open(path, 'rb') { |file| described_class.open_buffer(file, &:page_count) }).to eq(1)
      end
    end

    it 'rewinds the IO after reading it' do
      io = StringIO.new(docx)

      described_class.open_buffer(io, &:page_count)

      expect(io.pos).to eq(0)
      expect(io.read).to eq(docx)
    end

    it 'returns the block value and closes the document' do
      document = nil

      expect(described_class.open_buffer(docx) { |doc| (document = doc).to_pdf }).to start_with('%PDF-')
      expect(document).to be_closed
    end

    it 'closes the document when the block raises' do
      document = nil

      expect do
        described_class.open_buffer(docx) do |doc|
          document = doc
          raise 'boom'
        end
      end.to raise_error('boom')
      expect(document).to be_closed
    end

    it 'returns an open document without a block' do
      document = described_class.open_buffer(docx)

      expect(document).to be_a(WordCraft::Document)
      expect(document).not_to be_closed

      document.close

      expect(document).to be_closed
    end

    it 'raises WordCraft::Error for a file path' do
      expect { described_class.open_buffer('contract.docx') }.to raise_error(WordCraft::Error)
    end

    it 'raises ArgumentError for input that is not an IO or a String' do
      expect { described_class.open_buffer(42) }.to raise_error(ArgumentError)
    end

    it 'raises WordCraft::Error for bytes that are not a DOCX' do
      expect { described_class.open_buffer("not a docx \x00".b) }.to raise_error(WordCraft::Error)
    end

    it 'raises WordCraft::Error for a truncated DOCX' do
      expect { described_class.open_buffer(docx.byteslice(0, docx.bytesize / 2)) }.to raise_error(WordCraft::Error)
    end

    it 'raises WordCraft::Error for empty input' do
      expect { described_class.open_buffer('') }.to raise_error(WordCraft::Error, 'empty document')
    end
  end

  describe WordCraft::Document do
    subject(:document) { described_class.new(docx) }

    after { document.close }

    describe '#page_count' do
      it 'returns the number of pages' do
        expect(document.page_count).to eq(1)
      end
    end

    describe '#to_pdf' do
      it 'returns PDF bytes' do
        pdf = document.to_pdf

        expect(pdf).to start_with('%PDF-')
        expect(pdf.encoding).to eq(Encoding::BINARY)
        expect(pdf.rstrip).to end_with('%%EOF')
      end

      it 'converts with Print Markup' do
        expect(WordCraft.open_buffer(docx, markup: true, &:to_pdf)).to start_with('%PDF-')
      end
    end

    describe '#to_png' do
      it 'returns PNG bytes' do
        expect(document.to_png(page: 1)).to start_with("\x89PNG\r\n\x1A\n".b)
      end
    end

    describe '#to_jpeg' do
      it 'returns JPEG bytes' do
        expect(document.to_jpeg(page: 1, quality: 60)).to start_with("\xFF\xD8\xFF".b)
      end

      it 'raises ArgumentError for a quality outside 1..100' do
        expect { document.to_jpeg(page: 1, quality: 0) }.to raise_error(ArgumentError)
      end
    end

    describe '#to_rgba' do
      it 'returns the pixels, width and height' do
        pixels, width, height = document.to_rgba(page: 1, dpi: 72)

        expect([width, height]).to eq([612, 792])
        expect(pixels.bytesize).to eq(612 * 792 * 4)
        expect(pixels.encoding).to eq(Encoding::BINARY)
      end

      it 'scales with dpi' do
        expect(document.to_rgba(page: 1, dpi: 144).drop(1)).to eq([1224, 1584])
      end
    end

    it 'raises ArgumentError for a page that does not exist' do
      expect { document.to_png(page: 2) }.to raise_error(ArgumentError, 'page must be between 1 and 1, got 2')
      expect { document.to_png(page: 0) }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for a dpi that is not positive' do
      expect { document.to_png(page: 1, dpi: 0) }.to raise_error(ArgumentError)
    end

    it 'raises WordCraft::Error once closed' do
      document.close

      expect { document.to_pdf }.to raise_error(WordCraft::Error, 'document is closed')
      expect { document.to_png(page: 1) }.to raise_error(WordCraft::Error, 'document is closed')
      expect { document.close }.not_to raise_error
    end
  end

  describe '.add_font' do
    it 'adds no faces for bytes that are not a font' do
      expect(described_class.add_font('not a font'.b)).to eq(0)
    end

    it 'raises WordCraft::Error for empty input' do
      expect { described_class.add_font('') }.to raise_error(WordCraft::Error)
    end
  end

  describe '.load_system_fonts' do
    it 'returns the number of faces cataloged' do
      expect(described_class.load_system_fonts).to be >= 0
    end
  end

  describe WordCraft::Lib do
    it 'loads the library for this platform' do
      expect(described_class.ffi_libraries.map(&:name).join).to include(described_class::LIB_FILE)
    end
  end
end
