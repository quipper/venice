require 'json'
require 'net/https'
require 'uri'

module Venice
  ITUNES_PRODUCTION_RECEIPT_VERIFICATION_ENDPOINT = "https://buy.itunes.apple.com/verifyReceipt"
  ITUNES_DEVELOPMENT_RECEIPT_VERIFICATION_ENDPOINT = "https://sandbox.itunes.apple.com/verifyReceipt"

  class Client
    attr_accessor :verification_url
    attr_writer :shared_secret

    class << self
      def development
        client = self.new
        client.verification_url = ITUNES_DEVELOPMENT_RECEIPT_VERIFICATION_ENDPOINT
        client
      end

      def production
        client = self.new
        client.verification_url = ITUNES_PRODUCTION_RECEIPT_VERIFICATION_ENDPOINT
        client
      end
    end

    def initialize
      @verification_url = ENV['IAP_VERIFICATION_ENDPOINT']
    end

    def verify!(data, options = {})
      @verification_url ||= ITUNES_DEVELOPMENT_RECEIPT_VERIFICATION_ENDPOINT
      @shared_secret = options[:shared_secret] if options[:shared_secret]

      json = json_response_from_verifying_data(data)
      status, receipt_attributes = json['status'].to_i, json['receipt']

      case status
      when 0, 21006
        receipt = Receipt.new(receipt_attributes)

        # From Apple docs:
        # > Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions.
        # > The JSON representation of the receipt for the most recent renewal
        if latest_receipt_info_attributes = json['latest_receipt_info']
          # Apple sandbox retunrs 'latest_receipt_info' even if we use over iOS 6.
          # Besides, its format is not Hash but Array so Receipt.new would fail.
          if latest_receipt_info_attributes.is_a? Hash
            receipt.latest_receipt = Receipt.new(latest_receipt_info_attributes)
          end
        end

        return receipt
      else
        raise Receipt::VerificationError.new(status, receipt)
      end
    end

    private

    def json_response_from_verifying_data(data)
      parameters = {
        'receipt-data' => data
      }

      parameters['password'] = @shared_secret if @shared_secret

      uri = URI(@verification_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Accept'] = "application/json"
      request['Content-Type'] = "application/json"
      request.body = parameters.to_json

      response = http.request(request)

      JSON.parse(response.body)
    end
  end
end
