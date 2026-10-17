# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe WordCraft do
  let(:docx) { build_docx('Hello from Ruby', 'Second paragraph') }

  describe '.convert' do
    it 'returns PDF bytes' do
      pdf = described_class.convert(docx)

      expect(pdf).to start_with('%PDF-')
      expect(pdf.encoding).to eq(Encoding::BINARY)
      expect(pdf.rstrip).to end_with('%%EOF')
    end

    it 'converts with Print Markup' do
      expect(described_class.convert(docx, markup: true)).to start_with('%PDF-')
    end

    it 'raises WordCraft::Error for bytes that are not a DOCX' do
      expect { described_class.convert("not a docx \x00".b) }.to raise_error(WordCraft::Error)
    end

    it 'raises WordCraft::Error for a truncated DOCX' do
      expect { described_class.convert(docx.byteslice(0, docx.bytesize / 2)) }.to raise_error(WordCraft::Error)
    end

    it 'raises WordCraft::Error for empty input' do
      expect { described_class.convert('') }.to raise_error(WordCraft::Error, 'empty document')
    end

    it 'converts from several threads at once' do
      sizes = Array.new(4) { Thread.new { described_class.convert(docx).bytesize } }.map(&:value)

      expect(sizes.uniq.size).to eq(1)
    end
  end

  describe '.convert_file' do
    it 'writes the PDF to the output path' do
      Dir.mktmpdir do |dir|
        input = File.join(dir, 'in.docx')
        output = File.join(dir, 'out.pdf')
        File.binwrite(input, docx)

        expect(described_class.convert_file(input, output)).to eq(output)
        expect(File.binread(output, 5)).to eq('%PDF-')
      end
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
