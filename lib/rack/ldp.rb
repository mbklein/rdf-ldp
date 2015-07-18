require 'rack'
begin
  require 'linkeddata'
rescue LoadError => e
  require 'rdf/turtle'
  require 'json/ld'
end

require 'rack/linkeddata'
require 'rdf/ldp'

module Rack
  module LDP
    ##
    # Rack middleware for LDP responses
    class Headers
      CONSTRAINED_BY = RDF::URI('http://www.w3.org/ns/ldp#constrainedBy').freeze

      LINK_LDPR =  "<#{RDF::LDP::Resource.to_uri}>;rel=\"type\"".freeze
      LINK_LDPRS = '<http://www.w3.org/ns/ldp#RDFSource>;rel="type"'.freeze
      LINK_LDPNR = '<http://www.w3.org/ns/ldp#NonRDFSource>;rel="type"'.freeze
      LINK_BASIC_CONT = '<http://www.w3.org/ns/ldp#BasicContainer>;rel="type"'
                        .freeze

      ##
      # @param  [#call] app
      def initialize(app)
        @app = app
      end

      ##
      # Handles a Rack protocol request. 
      def call(env)
        status, headers, response = @app.call(env)

        headers['Link'] = 
          ([headers['Link']] + link_headers(response)).compact.join("\n")

        etag = etag(response)
        headers['Etag'] ||= etag if etag
        
        if response.respond_to? :to_response
          new_response = response.to_response
          response.close if response.respond_to? :close
          response = new_response
        end

        [status, headers, response]
      end

      private

      ##
      # @param [Object] response
      # @return [String]
      def etag(response)
        return response.etag if response.respond_to? :etag
        nil
      end
      
      ##
      # @param [Object] response
      # @return [Array<String>] an array of link headers to add to the 
      #   existing ones
      #
      # @see http://www.w3.org/TR/ldp/#h-ldpr-gen-linktypehdr
      # @see http://www.w3.org/TR/ldp/#h-ldprs-are-ldpr
      # @see http://www.w3.org/TR/ldp/#h-ldpnr-type
      # @see http://www.w3.org/TR/ldp/#h-ldpc-linktypehdr
      def link_headers(response)
        return [] unless response.is_a? RDF::LDP::Resource
        headers = [LINK_LDPR]
        headers << LINK_LDPRS if response.rdf_source?
        headers << LINK_LDPNR if response.non_rdf_source?
        headers
      end
    end

    ##
    # Specializes {Rack::LinkedData::ContentNegotiation}, making the default 
    # return type 'text/turtle'
    class ContentNegotiation < Rack::LinkedData::ContentNegotiation
      def initialize(app, options = {})
        options[:default] ||= 'text/turtle'
        super
      end
    end
  end
end

