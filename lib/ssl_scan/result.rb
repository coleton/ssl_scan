require 'set'

module SSLScan
  class Result

    attr_accessor :openssl_sslv2

    attr_reader :ciphers
    attr_reader :supported_versions
    attr_reader :peer_verified

    def initialize()
      @cert = nil
      @ciphers = Set.new
      @peer_verified = false
      @supported_versions = [:SSLv2, :SSLv3, :TLSv1]
    end

    def cert
      @cert
    end

    def cert=(input)
      unless input.kind_of? OpenSSL::X509::Certificate or input.nil?
        raise ArgumentError, "Must be an X509 Cert!"
      end
      @cert = input
    end

    def sslv2
      @ciphers.reject{|cipher| cipher[:version] != :SSLv2 }
    end

    def sslv3
      @ciphers.reject{|cipher| cipher[:version] != :SSLv3 }
    end

    def tlsv1
      @ciphers.reject{|cipher| cipher[:version] != :TLSv1 }
    end

    def rc4_md5
      @ciphers.reject{|cipher| cipher[:cipher] != "RC4-MD5" }
    end

    def weak_ciphers
      accepted.reject{|cipher| cipher[:weak] == false }
    end

    def strong_ciphers
      accepted.reject{|cipher| cipher[:weak] }
    end

    # Returns all accepted ciphers matching the supplied version
    # @param version [Symbol, Array] The SSL Version to filter on
    # @raise [ArgumentError] if the version supplied is invalid
    # @return [Array] An array of accepted cipher details matching the supplied versions
    def accepted(version = :all)
      enum_ciphers(:accepted, version)
    end

    # Returns all rejected ciphers matching the supplied version
    # @param version [Symbol, Array] The SSL Version to filter on
    # @raise [ArgumentError] if the version supplied is invalid
    # @return [Array] An array of rejected cipher details matching the supplied versions
    def rejected(version = :all)
      enum_ciphers(:rejected, version)
    end

    def failed(version = :all)
      enum_ciphers(:failed, version)
    end

    def each_accepted(version = :all)
      accepted(version).each do |cipher_result|
        yield cipher_result
      end
    end

    def each_rejected(version = :all)
      rejected(version).each do |cipher_result|
        yield cipher_result
      end
    end

    def supports_sslv2?
      !(accepted(:SSLv2).empty?)
    end

    def supports_sslv3?
      !(accepted(:SSLv3).empty?)
    end

    def supports_tlsv1?
      !(accepted(:TLSv1).empty?)
    end

    def supports_ssl?
      supports_sslv2? or supports_sslv3? or supports_tlsv1?
    end

    def supports_weak_ciphers?
      !(weak_ciphers.empty?)
    end

    def supports_rc4_md5_ciphers?
      !(rc4_md5.empty?)
    end

    def standards_compliant?
      if supports_ssl?
        return false if supports_sslv2?
        return false if supports_weak_ciphers?
      end
      true
    end

    # Adds the details of a cipher test to the Result object.
    # @param version [Symbol] the SSL Version
    # @param cipher [String] the SSL cipher
    # @param key_length [Fixnum] the length of encryption key
    # @param status [Symbol] :accepted or :rejected
    def add_cipher(version, cipher, key_length, status)
      unless @supported_versions.include? version
        raise ArgumentError, "Must be a supported SSL Version"
      end
      unless OpenSSL::SSL::SSLContext.new(version).ciphers.flatten.include? cipher
        raise ArgumentError, "Must be a valid SSL Cipher for #{version}!"
      end
      unless key_length.kind_of? Fixnum
        raise ArgumentError, "Must supply a valid key length"
      end
      unless [:accepted, :rejected, :failed].include? status
        raise ArgumentError, "Status must be either :accepted or :rejected"
      end

      strong_cipher_ctx = OpenSSL::SSL::SSLContext.new(version)
      # OpenSSL Directive For Strong Ciphers
      # Updated from OWASP
      # See: https://www.owasp.org/index.php/Transport_Layer_Protection_Cheat_Sheet#Rule_-_Only_Support_Strong_Cryptographic_Ciphers
      tmp_ciphers = "EDH+aRSA+AESGCM:EDH+aRSA+AES:DHE-RSA-AES256-SHA"
      tmp_ciphers += ":EECDH+aRSA+AESGCM:EECDH+aRSA+AES:ECDHE-RSA-AES256-SHA"
      tmp_ciphers += ":ECDHE-RSA-AES128-SHA:RSA+AESGCM:RSA+AES+SHA:DES-CBC3-SHA"
      tmp_ciphers += ":-DHE-RSA-AES128-SHA:!aNULL:!eNULL:!LOW:!MD5:!EXP:!PSK:!DSS"
      tmp_ciphers += ":!RC4:!SEED:!ECDSA:!ADH:!IDEA"
      strong_cipher_ctx.ciphers = tmp_ciphers

      if strong_cipher_ctx.ciphers.flatten.include? cipher
        weak = false
      else
        weak = true
      end

      cipher_details = {:version => version, :cipher => cipher, :key_length => key_length, :weak => weak, :status => status}
      @ciphers << cipher_details
    end

    protected

    # @param state [Symbol] Either :accepted or :rejected
    # @param version [Symbol, Array] The SSL Version to filter on (:SSLv2, :SSLv3, :TLSv1, :all)
    # @return [Set] The Set of cipher results matching the filter criteria
    def enum_ciphers(state, version = :all)
      case version
      when Symbol
        case version
        when :all
          return @ciphers.select { |cipher| cipher[:status] == state }
        when :SSLv2, :SSLv3, :TLSv1
          return @ciphers.select { |cipher| cipher[:status] == state and cipher[:version] == version }
        else
          raise ArgumentError, "Invalid SSL Version Supplied: #{version}"
        end
      when Array
        version = version.reject{|v| !(@supported_versions.include? v)}
        if version.empty?
          return @ciphers.select{|cipher| cipher[:status] == state}
        else
          return @ciphers.select{|cipher| cipher[:status] == state and version.include? cipher[:version]}
        end
      else
        raise ArgumentError, "Was expecting Symbol or Array and got #{version.class}"
      end
    end

  end
end
