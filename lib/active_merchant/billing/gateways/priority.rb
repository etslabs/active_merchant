module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PriorityGateway < Gateway
      # Sandbox and Production
      self.test_url = 'https://sandbox.api.mxmerchant.com/checkout/v3/payment'
      self.live_url = 'https://api.mxmerchant.com/checkout/v3/payment'

      class_attribute :test_url_verify, :live_url_verify, :test_auth, :live_auth, :test_env_verify, :live_env_verify, :test_url_batch, :live_url_batch, :test_url_jwt, :live_url_jwt, :merchant

      # Sandbox and Production - verify card
      self.test_url_verify = 'https://sandbox-api2.mxmerchant.com/merchant/v1/bin'
      self.live_url_verify = 'https://api2.mxmerchant.com/merchant/v1/bin'

      # Sandbox and Production - check batch status
      self.test_url_batch = 'https://sandbox.api.mxmerchant.com/checkout/v3/batch'
      self.live_url_batch = 'https://api.mxmerchant.com/checkout/v3/batch'

      # Sandbox and Production - generate jwt for veriy card url
      self.test_url_jwt = 'https://sandbox-api2.mxmerchant.com/security/v1/application/merchantId'
      self.live_url_jwt = 'https://api2.mxmerchant.com/security/v1/application/merchantId'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover]

      self.homepage_url = 'https://mxmerchant.com/'
      self.display_name = 'Priority'

      def initialize(options = {})
        requires!(options, :merchant_id, :key, :secret)
        super
      end

      def basic_auth
        Base64.strict_encode64("#{@options[:key]}:#{@options[:secret]}")
      end

      def request_headers
        {
          'Content-Type' => 'application/json',
          'Authorization' => "Basic #{basic_auth}"
        }
      end

      def request_verify_headers(jwt)
        {
          'Authorization' => "Bearer #{jwt}"
        }
      end

      def purchase(amount, credit_card, options = {})
        params = {}
        params['amount'] = localized_amount(amount.to_f, options[:currency])
        params['authOnly'] = false

        add_credit_card(params, credit_card, 'purchase', options)
        add_type_merchant_purchase(params, @options[:merchant_id], true, options)
        commit('purchase', params: params, jwt: options)
      end

      def authorize(amount, credit_card, options = {})
        params = {}
        params['amount'] = localized_amount(amount.to_f, options[:currency])
        params['authOnly'] = true

        add_credit_card(params, credit_card, 'purchase', options)
        add_type_merchant_purchase(params, @options[:merchant_id], false, options)
        commit('purchase', params: params, jwt: options)
      end

      def refund(amount, credit_card, options)
        params = {}
        # refund amounts must be negative
        params['amount'] = ('-' + localized_amount(amount.to_f, options[:currency])).to_f

        add_bank(params, options[:auth_code])
        add_credit_card(params, credit_card, 'refund', options) unless options[:auth_code]
        add_type_merchant_refund(params, options)
        commit('refund', params: params, jwt: options)
      end

      def capture(amount, authorization, options = {})
        params = {}
        params['amount'] = localized_amount(amount.to_f, options[:currency])
        params['authCode'] = options[:authCode]
        params['merchantId'] = @options[:merchant_id]
        params['paymentToken'] = authorization
        params['shouldGetCreditCardLevel'] = true
        params['source'] = options['source']
        params['tenderType'] = options[:tender_type]

        commit('capture', params: params, jwt: options)
      end

      def void(iid, options)
        commit('void', iid: iid, jwt: options)
      end

      def verify(credit_card, jwt)
        commit('verify', card_number: credit_card, jwt: jwt)
      end

      def supports_scrubbing?
        true
      end

      def get_payment_status(batch_id, options)
        commit('get_payment_status', params: batch_id, jwt: options)
      end

      def close_batch(batch_id, options)
        commit('close_batch', params: batch_id, jwt: options)
      end

      def create_jwt(options)
        commit('create_jwt', params: @options[:merchant_id], jwt: options)
      end

      def scrub(transcript)
        transcript.
          gsub(%r((Authorization: Basic )\w+), '\1[FILTERED]').
          gsub(%r((number\\?"\s*:\s*\\?")[^"]*)i, '\1[FILTERED]').
          gsub(%r((cvv\\?"\s*:\s*\\?")[^"]*)i, '\1[FILTERED]')
      end

      def add_bank(params, auth_code)
        params['authCode'] = auth_code
        params['authMessage'] = ''
        params['authOnly'] = false
        params['availableAuthAmount'] = 0
        params['batch'] = nil
        params['batchId'] = nil
      end

      def add_credit_card(params, credit_card, action, options)
        return unless credit_card

        card_details = {}

        case action
        when 'purchase'
          card_details['avsStreet'] = options[:billing_address][:address1]
          card_details['avsZip'] =  options[:billing_address][:zip]
          card_details['cvv'] = credit_card.verification_value
          card_details['entryMode'] = 'Keyed'
          card_details['expiryDate'] = exp_date(credit_card)
          card_details['expiryMonth'] = format(credit_card.month, :two_digits).to_s
          card_details['expiryYear'] = format(credit_card.year, :two_digits).to_s
          card_details['last4'] = nil
          card_details['magstripe'] = nil
          card_details['number'] = credit_card.number
        when 'refund'
          card_details['cardId'] = credit_card['cardId']
          card_details['cardPresent'] = credit_card['cardPresent']
          card_details['cardType'] = credit_card['cardType']
          card_details['entryMode'] = credit_card['entryMode']
          card_details['expiryMonth'] = credit_card['expiryMonth']
          card_details['expiryYear'] = credit_card['expiryYear']
          card_details['hasContract'] = credit_card['hasContract']
          card_details['isCorp'] = credit_card['isCorp']
          card_details['isDebit'] = credit_card['isDebit']
          card_details['last4'] = credit_card['last4']
          card_details['token'] = credit_card['token']
        end

        params['cardAccount'] = card_details
      end

      def exp_date(credit_card)
        "#{format(credit_card.month, :two_digits)}/#{format(credit_card.year, :two_digits)}"
      end

      def purchases
        [{ taxRate: '0.0000', additionalTaxRate: nil, discountRate: nil }]
      end

      def add_type_merchant_purchase(params, merchant, is_settle_funds, options)
        params['cardPresent'] = false
        params['cardPresentType'] = 'CardNotPresent'
        params['isAuth'] = true
        params['isSettleFunds'] = is_settle_funds
        params['isTicket'] = false

        params['merchantId'] = merchant
        params['mxAdvantageEnabled'] = false
        params['mxAdvantageFeeLabel'] = ''
        params['paymentType'] = 'Sale'
        params['bankAccount'] = nil

        params['purchases'] = purchases

        params['shouldGetCreditCardLevel'] = true
        params['shouldVaultCard'] = true
        params['source'] = options['source']
        params['sourceZip'] = options[:billing_address][:zip]
        params['taxExempt'] = false
        params['tenderType'] = options[:tender_type]
        params['terminals'] = []
      end

      def add_type_merchant_refund(params, options)
        params['cardPresent'] = options['cardPresent']
        params['clientReference'] = options['clientReference']
        params['created'] = options['created']
        params['creatorName'] = options['creatorName']
        params['currency'] = options['currency']
        params['customerCode'] = options['customerCode']
        params['enteredAmount'] = options['amount']
        params['id'] = 0
        params['invoice'] = options['invoice']
        params['isDuplicate'] = false
        params['merchantId'] = @options[:merchant_id]
        params['paymentToken'] = options['cardAccount']['token'] if options['cardAccount']

        params['posData'] = options['posData']

        params['purchases'] = options['purchases']

        params['reference'] = options['reference']
        params['replayId'] = nil
        params['requireSignature'] = false
        params['reviewIndicator'] = nil

        params['risk'] = options['risk']

        params['settledAmount'] = options['settledAmount']
        params['settledCurrency'] = options['settledCurrency']
        params['settledDate'] = options['created']
        params['shipToCountry'] = options['shipToCountry']
        params['shouldGetCreditCardLevel'] = options['shouldGetCreditCardLevel']
        params['source'] = options['source']
        params['sourceZip'] = nil
        params['status'] = options['status']
        params['tax'] = options['tax']
        params['taxExempt'] = options['taxExempt']
        params['tenderType'] = options['tender_type']
        params['type'] = options['type']
      end

      def commit(action, params: '', iid: '', card_number: '', jwt: '')
        response =
          begin
            case action
            when 'void'
              ssl_request(:delete, url(action, params, ref_number: iid), nil, request_headers)
            when 'verify'
              parse(ssl_get(url(action, params, credit_card_number: card_number), request_verify_headers(jwt)))
            when 'get_payment_status', 'create_jwt'
              parse(ssl_get(url(action, params, ref_number: iid), request_headers))
            when 'close_batch'
              ssl_request(:put, url(action, params, ref_number: iid), nil, request_headers)
            else
              parse(ssl_post(url(action, params), post_data(params), request_headers))
            end
          rescue ResponseError => e
            parse(e.response.body)
          end
        success = success_from(response)

        response = { 'code' => '204' } if response == ''
        Response.new(
          success,
          message_from(success, response),
          response,
          authorization: success && response['code'] != '204' ? authorization_from(response) : nil,
          error_code: success || response['code'] == '204' || response == '' ? nil : error_from(response),
          test: test?
        )
      end

      def handle_response(response)
        if response.code != '204' && (200...300).cover?(response.code.to_i)
          response.body
        elsif response.code == '204' || response == ''
          response.body = { 'code' => '204' }
        else
          raise ResponseError.new(response)
        end
      end

      def url(action, params, ref_number: '', credit_card_number: '')
        case action
        when 'void'
          base_url + "/#{ref_number}?force=true"
        when 'verify'
          (verify_url + '?search=') + (credit_card_number[0, 6]).to_s
        when 'get_payment_status', 'close_batch'
          batch_url + "/#{params}"
        when 'create_jwt'
          jwt_url + "/#{params}/token"
        else
          base_url + '?includeCustomerMatches=false&echo=true'
        end
      end

      def base_url
        test? ? test_url : live_url
      end

      def verify_url
        test? ? self.test_url_verify : self.live_url_verify
      end

      def jwt_url
        test? ? self.test_url_jwt : self.live_url_jwt
      end

      def batch_url
        test? ? self.test_url_batch : self.live_url_batch
      end

      def parse(body)
        JSON.parse(body)
      rescue JSON::ParserError
        message = 'Invalid JSON response received from Priority Gateway. Please contact Priority Gateway if you continue to receive this message.'
        message += " (The raw response returned by the API was #{body.inspect})"
        {
          'message' => message
        }
      end

      def success_from(response)
        response['status'] == 'Approved' || response['status'] == 'Open' if response['status']
      end

      def message_from(succeeded, response)
        if succeeded
          response['status']
        else
          response['authMessage']
        end
      end

      def authorization_from(response)
        response['paymentToken']
      end

      def error_from(response)
        response['errorCode']
      end

      def post_data(params)
        params.to_json
      end
    end
  end
end
