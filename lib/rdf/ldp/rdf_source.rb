require 'digest/md5'

module RDF::LDP
  ##
  # The base class for all directly usable LDP Resources that *are not* 
  # `NonRDFSources`. RDFSources are implemented as a resource with:
  #
  #   - a `#subject_uri` identifying the RDFSource (see: {RDF::LDP::Resource}).
  #   - a `#graph` representing the "entire persistent state"
  #   - a `#metagraph` containing internal properties of the RDFSource
  #
  # Persistence schemes must be able to reconstruct both `#graph` and 
  # `#metagraph` accurately and separately (e.g. by saving them as distinct
  # named graphs). Statements in `#metagraph` are considered canonical for the
  # purposes of server-side operations; in the `RDF::LDP` core, this means they
  # determine interaction model.
  #
  # Note that the contents of `#metagraph`'s are *not* the same as 
  # LDP-server-managed triples. `#metagraph` contains statements internal 
  # properties of the RDFSource which are necessary for the server's management
  # purposes, but MAY be absent from the representation of its state in `#graph`.
  # `#metagraph` is invisible to the client unless the implementation mirrors
  # its contents in `#graph`.
  # 
  # @see http://www.w3.org/TR/ldp/#dfn-linked-data-platform-rdf-source definition 
  #   of ldp:RDFSource in the LDP specification
  class RDFSource < Resource
    attr_accessor :graph

    class << self
      ##
      # @return [RDF::URI] uri with lexical representation 
      #   'http://www.w3.org/ns/ldp#RDFSource'
      #
      # @see http://www.w3.org/TR/ldp/#dfn-linked-data-platform-rdf-source
      def to_uri 
        RDF::Vocab::LDP.RDFSource
      end
    end
    
    def initialize(subject_uri, data = RDF::Repository.new)
      @graph = RDF::Graph.new(subject_uri, data: data)
      super
      self
    end

    ##
    # Creates the RDFSource, populating its graph from the input given
    #
    # @param [IO, File, #to_s] input  input (usually from a Rack env's 
    #   `rack.input` key) used to determine the Resource's initial state.
    # @param [#to_s] content_type  a MIME content_type used to read the graph.
    #
    # @raise [RDF::LDP::RequestError] 
    # @raise [RDF::LDP::UnsupportedMediaType] if no reader can be found for the 
    #   graph
    # @raise [RDF::LDP::BadRequest] if the identified reader can't parse the 
    #   graph
    # @raise [RDF::LDP::Conflict] if the RDFSource already exists
    #
    # @return [RDF::LDP::Resource] self
    def create(input, content_type)
      super
      statements = parse_graph(input, content_type)
      graph << statements
      self
    end

    ##
    # Updates the resource. Replaces the contents of `graph` with the parsed 
    # input.
    #
    # @param [IO, File, #to_s] input  input (usually from a Rack env's 
    #   `rack.input` key) used to determine the Resource's new state.
    # @param [#to_s] content_type  a MIME content_type used to interpret the
    #   input.
    #
    # @return [RDF::LDP::Resource] self
    def update(input, content_type)
      return create(input, content_type) unless exists?
      statements = parse_graph(input, content_type)
      graph.clear!
      graph << statements
      self
    end

    ##
    # Returns an Etag. This may be a strong or a weak ETag.
    #
    # @return [String] an HTTP Etag 
    #
    # @note the current implementation is a naive one that combines a couple of 
    # blunt heurisitics. 
    # 
    # @todo add an efficient hash function for RDF Graphs to RDF.rb and use that
    #   here?
    #
    # @see http://ceur-ws.org/Vol-1259/proceedings.pdf#page=65 for a recent
    #   treatment of digests for RDF graphs
    #
    # @see http://www.w3.org/TR/ldp#h-ldpr-gen-etags  LDP ETag clause for GET
    # @see http://www.w3.org/TR/ldp#h-ldpr-put-precond  LDP ETag clause for PUT
    # @see http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.3.3 
    #   description of strong vs. weak validators
    def etag
      subs = graph.subjects.map { |s| s.node? ? nil : s.to_s }
             .compact.sort.join()
      "#{Digest::MD5.base64digest(subs)}#{graph.statements.count}"
    end

    ##
    # @param [String] tag  a tag to compare to `#etag`
    # @return [Boolean] whether the given tag matches `#etag`
    def match?(tag)
      return false unless tag.split('==').last == graph.statements.count
      tag == etag
    end

    ##
    # @return [Boolean] whether this is an ldp:RDFSource
    def rdf_source?
      true
    end

    ##
    # @return [RDF::URI] the subject URI for this resource
    def to_uri
      subject_uri
    end

    ##
    # Returns the graph representing this resource's state, without the graph 
    # context.
    def to_response
      RDF::Graph.new << graph
    end

    private

    ##
    # Generate response for PUT requsets.
    def put(status, headers, env)
      if exists?
        update(env['rack.input'], env['CONTENT_TYPE'])
        headers = update_headers(headers)
        [200, headers, self]
      else
        create(env['rack.input'], env['CONTENT_TYPE'])
        [201, update_headers(headers), self]
      end
    end

    ##
    # Finds an {RDF::Reader} appropriate for the given content_type and attempts
    # to parse the graph string.
    #
    # @param [IO, File, String] graph  an input stream to parse
    # @param [#to_s] content_type  the content type for the reader
    #
    # @return [RDF::Enumerable] the statements in the resulting graph
    #
    # @raise [RDF::LDP::UnsupportedMediaType] if no appropriate reader is found
    #
    # @todo handle cases where no content type is given? Does RDF::Reader have 
    #   tools to help us here?
    def parse_graph(graph, content_type)
      reader = RDF::Reader.for(content_type: content_type.to_s)
      raise(RDF::LDP::UnsupportedMediaType, content_type) if reader.nil?
      begin
        RDF::Graph.new << reader.new(graph, base_uri: subject_uri)
      rescue RDF::ReaderError => e
        raise RDF::LDP::BadRequest, e.message
      end  
    end
  end
end
