require 'timecop'

shared_examples 'a Resource' do
  describe '.to_uri' do
    it { expect(described_class.to_uri).to be_a RDF::URI }
  end

  subject { described_class.new(uri) }
  let(:uri) { RDF::URI 'http://example.org/moomin' }

  it { is_expected.to be_ldp_resource }
  it { is_expected.to respond_to :container? }
  it { is_expected.to respond_to :rdf_source? }
  it { is_expected.to respond_to :non_rdf_source? }

  it { subject.send(:set_last_modified) }

  describe '#allowed_methods' do
    it 'responds to all methods returned' do
      subject.allowed_methods.each do |method|
        expect(subject.respond_to?(method.downcase, true)).to be true
      end
    end

    it 'includes the MUST methods' do
      expect(subject.allowed_methods).to include(*[:GET, :OPTIONS, :HEAD])
    end
  end

  describe '#create' do
    it 'accepts two args' do
      expect(described_class.instance_method(:create).arity).to eq 2
    end

    describe 'modified time' do
      before { Timecop.freeze }
      after  { Timecop.return }

      it 'sets last_modified' do
        subject.create(StringIO.new(''), 'text/turtle')
        expect(subject.last_modified).to eq DateTime.now
      end
    end

    it 'adds a type triple to metagraph' do
      subject.create(StringIO.new(''), 'text/plain')
      expect(subject.metagraph)
        .to have_statement RDF::Statement(subject.subject_uri, 
                                          RDF.type, 
                                          described_class.to_uri)
    end

    it 'marks resource as existing' do
      expect { subject.create(StringIO.new(''), 'text/plain') }
        .to change { subject.exists? }.from(false).to(true)
    end

    it 'raises Conlict when already exists' do
      subject.create(StringIO.new(''), 'text/plain')
      expect { subject.create(StringIO.new(''), 'text/plain') }
        .to raise_error RDF::LDP::Conflict
    end
  end

  describe '#update' do
    it 'accepts two args' do
      expect(described_class.instance_method(:update).arity).to eq 2
    end
  end

  describe '#destroy' do
    it 'accepts no args' do
      expect(described_class.instance_method(:destroy).arity).to eq 0
    end
  end

  describe '#metagraph' do
    it 'returns a graph' do
      expect(subject.metagraph).to be_a RDF::Graph
    end

    it 'has the metagraph name for the resource' do
      expect(subject.metagraph.context).to eq subject.subject_uri / '#meta'
    end
  end

  describe '#etag' do
    before { subject.create(StringIO.new(''), 'text/plain') }
    
    it 'has an etag' do
      expect(subject.etag).to be_a String
    end

    it 'updates etag on change' do
      expect { subject.update(StringIO.new(''), 'text/plain') }
        .to change { subject.etag }
    end
  end

  describe '#last_modified' do
    before do
      subject.metagraph.update([subject.subject_uri, 
                                RDF::DC.modified, 
                                datetime])
    end

    let(:datetime) { DateTime.now }

    it 'returns date in `dc:modified`' do
      expect(subject.last_modified).to eq datetime
    end
  end

  describe '#to_response' do
    it 'returns an object that responds to #each' do
      expect(subject.to_response).to respond_to :each
    end
  end

  describe '#request' do
    it 'sends the message to itself' do
      expect(subject).to receive(:blah)
      subject.request(:BLAH, 200, {}, {})
    end

    it 'raises MethodNotAllowed when method is unimplemented' do
      allow(subject).to receive(:not_implemented)
                         .and_raise NotImplementedError
      expect { subject.request(:not_implemented, 200, {}, {}) }
        .to raise_error(RDF::LDP::MethodNotAllowed)
    end

    it 'raises MethodNotAllowed when method is not present' do
      allow(subject).to receive(:no_method)
                         .and_raise NoMethodError
      expect { subject.request(:no_method, 200, {}, {}) }
        .to raise_error(RDF::LDP::MethodNotAllowed)
    end

    describe 'HTTP headers' do
      before { subject.create(StringIO.new(''), 'text/turtle') }
      let(:headers) { subject.request(:GET, 200, {}, {})[1] }
      
      it 'has ETag' do
        expect(headers['ETag']).to eq subject.etag
      end

      it 'has Last-Modified' do
        expect(headers['Last-Modified']).to eq subject.last_modified
      end

      it 'has Allow' do
        expect(headers['Allow']).to be_a String
      end

      it 'has Link' do
        expect(headers['Link']).to be_a String
      end
    end

    it 'responds to :GET' do
      expect { subject.request(:GET, 200, {}, {}) }.not_to raise_error
    end

    it 'responds to :HEAD' do
      expect { subject.request(:OPTIONS, 200, {}, {}) }.not_to raise_error
    end

    it 'responds to :OPTIONS' do
      expect { subject.request(:OPTIONS, 200, {}, {}) }.not_to raise_error
    end
  end
end
