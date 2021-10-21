require 'test_helper'

class RemotePriorityTest < Test::Unit::TestCase
  def setup
    # Consumer API Key: Generated in MX Merchant for specific test merchant
    # Consumer API Secret:= Generated in MX Merchant for specific test merchant

    # run command below to run tests in debug (byebug)
    # byebug -Itest test/unit/gateways/card_stream_test.rb
    #
    # bundle exec rake test:remote TEST=test/remote/gateways/remote_priority_test.rb
    # ruby -Itest test/unit/gateways/priority_test.rb -n test_successful_void

    # Run specific remote test
    # ruby -Itest test/remote/gateways/remote_priority_test.rb -n test_fail_refund_already_refunded_purchase_response
    @gateway = PriorityGateway.new(fixtures(:priority))

    # purchase params success
    @amount_purchase = 2.11
    @credit_card_purchase_success = credit_card('4111111111111111', month: '01', year: '2029', first_name: 'Marcus', last_name: 'Rashford', verification_value: '999')

    @option_spr = {
      billing_address: address(),
      avsStreet: '666',
      avsZip: '55044',
      tender_type: 'Card'
    }

    # purchase params fail inavalid card number
    @credit_card_purchase_fail_invalid_number = credit_card('4111', month: '01', year: '2029', first_name: 'Marcus', last_name: 'Rashford', verification_value: '999')

    # purchase params fail missing card number month
    @credit_card_purchase_fail_missing_month = credit_card('4111111111111111', month: '', year: '2029', first_name: 'Marcus', last_name: 'Rashford', verification_value: '999')

    # purchase params fail missing card verification number
    @credit_card_purchase_fail_missing_verification = credit_card('4111111111111111', month: '01', year: '2029', first_name: 'Marcus', last_name: 'Rashford', verification_value: '')

    # authorize params success
    @amount_authorize = 7.99
    # authorize params success end

    # verify params
    @iid = '10000001617842'
    @card_number_verify = '4111111111111111'
    # verify params end

    # Refund params
    @amount_refund = -4.32
    @credit_card_refund = {
      cardId: 'y15QvOteHZGBm7LH3GNIlTWbA1If',
      cardPresent: false,
      cardType: 'Visa',
      entryMode: 'Keyed',
      expiryMonth: '02',
      expiryYear: '29',
      hasContract: false,
      isCorp: false,
      isDebit: false,
      last4: '1111',
      token: 'P4A4gziiGpRgiHyAec1rl1FLafaVUMY6'
    }

    # Used by Refund tests
    @response_purchase = {
      "created": '2021-09-08T18:47:38.543Z',
      "paymentToken": 'PfD0LBepsr2cRR9H5qrUsGrpvHFIs7eG',
      "id": 10000001649674,
      "creatorName": 'Mike B',
      "isDuplicate": false,
      "shouldVaultCard": true,
      "batch": '0042',
      "batchId": 10000000229441,
      "tenderType": 'Card',
      "currency": 'USD',
      "amount": '3.33',
      "cardAccount": {
        "cardType": 'Visa',
          "entryMode": 'Keyed',
          "last4": '1111',
          "cardId": 'y15QvOteHZGBm7LH3GNIlTWbA1If',
          "token": 'PfD0LBepsr2cRR9H5qrUsGrpvHFIs7eG',
          "expiryMonth": '02',
          "expiryYear": '29',
          "hasContract": false,
          "cardPresent": false,
          "isDebit": false,
          "isCorp": false
      },
      "posData": {
        "panCaptureMethod": 'Manual'
      },
      "authOnly": false,
      "authCode": 'PPS6fd',
      "status": 'Approved',
      "risk": {
        "cvvResponseCode": 'M',
          "cvvResponse": 'Match',
          "cvvMatch": true,
          "avsResponse": 'No Response from AVS',
          "avsAddressMatch": false,
          "avsZipMatch": false
      },
      "requireSignature": false,
      "settledAmount": '0',
      "settledCurrency": 'USD',
      "cardPresent": false,
      "authMessage": 'Approved or completed successfully. ',
      "availableAuthAmount": '0',
      "reference": '125118000500',
      "tax": '0.04',
      "invoice": 'T004AAIY',
      "customerCode": 'PTHLT004AAIY',
      "shipToCountry": 'USA',
      "purchases": [
        {
          "dateCreated": '0001-01-01T00:00:00',
            "iId": 0,
            "transactionIId": 0,
            "transactionId": '0',
            "name": 'Miscellaneous',
            "description": 'Miscellaneous',
            "code": 'MISC',
            "unitOfMeasure": 'EA',
            "unitPrice": '3.29',
            "quantity": 1,
            "taxRate": '0.0121580547112462006079027356',
            "taxAmount": '0.04',
            "discountRate": '0',
            "discountAmount": '0',
            "extendedAmount": '3.33',
            "lineItemId": 0
        }
      ],
      "clientReference": 'PTHLT004AAIY',
      "type": 'Sale',
      "taxExempt": false,
      "reviewIndicator": 1,
      "source": 'QuickPay',
      "shouldGetCreditCardLevel": false
    }
    # Refund params end
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_success, @option_spr)
    assert_success response
    assert_equal 'Approved', response.params['status']
  end

  # Invalid card number
  def test_failed_purchase
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_fail_invalid_number, @option_spr)
    assert_failure response

    assert_equal 'Invalid card number', response.params['authMessage']
    assert_equal 'Declined', response.params['status']
  end

  # Missing card number month
  def test_failed_purchase_missing_card_month
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_fail_missing_month, @option_spr)
    assert_failure response

    assert_equal 'ValidationError', response.params['errorCode']
    assert_equal 'Validation error happened', response.params['message']
    assert_equal 'Missing expiration month and / or year', response.params['details'][0]
  end

  # Missing card verification number
  def test_failed_purchase_missing_card_verification_number
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_fail_missing_verification, @option_spr)
    assert_failure response

    assert_equal 'CVV is required based on merchant fraud settings', response.params['authMessage']
    assert_equal 'Declined', response.params['status']
  end

  # Authorize tests
  def test_successful_authorize
    response = @gateway.authorize(@amount_purchase, @credit_card_purchase_success, @option_spr)
    assert_success response
    assert_equal 'Approved', response.params['status']
  end

  # Invalid card number
  def test_failed_authorize
    response = @gateway.authorize(@amount_purchase, @credit_card_purchase_fail_invalid_number, @option_spr)
    assert_failure response

    assert_equal 'Invalid card number', response.params['authMessage']
    assert_equal 'Declined', response.params['status']
  end

  # Missing card number month
  def test_failed_authorize_missing_card_month
    response = @gateway.authorize(@amount_purchase, @credit_card_purchase_fail_missing_month, @option_spr)
    assert_failure response

    assert_equal 'ValidationError', response.params['errorCode']
    assert_equal 'Validation error happened', response.params['message']
    assert_equal 'Missing expiration month and / or year', response.params['details'][0]
  end

  # Missing card verification number
  def test_failed_authorize_missing_card_verification_number
    response = @gateway.authorize(@amount_purchase, @credit_card_purchase_fail_missing_verification, @option_spr)
    assert_failure response

    assert_equal 'CVV is required based on merchant fraud settings', response.params['authMessage']
    assert_equal 'Declined', response.params['status']
  end

  # Capture tests
  def test_successful_capture
    auth_obj = @gateway.authorize(@amount_authorize, @credit_card_purchase_success, @option_spr)
    assert_success auth_obj
    # add auth code to options
    @option_spr.update(authCode: auth_obj.params['authCode'])

    capture = @gateway.capture(@amount_authorize, auth_obj.authorization, @option_spr)
    assert_success capture
    assert_equal 'Approved', capture.params['authMessage']
    assert_equal 'Approved', capture.params['status']
  end

  # Invalid authorization and null auth code
  def test_failed_capture
    # add auth code to options
    @option_spr.update(authCode: '12345')
    capture = @gateway.capture(@amount_authorize, 'bogus', @option_spr)
    assert_failure capture

    assert_equal 'Original Transaction Not Found', capture.params['authMessage']
    assert_equal 'Declined', capture.params['status']
  end

  # Void tests
  # Batch status is by default is set to Open wehn Sale transaction is created
  def test_successful_void_batch_open
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_success, @option_spr)
    assert_success response

    # check is this transaction associated batch is "Closed".
    batch_check = @gateway.get_payment_status(response.params['batchId'], @option_spr)
    # if batch Open then fail test. Batch must be closed to perform a Refund
    if batch_check.params['status'] == 'Open'
      @gateway.void(response.params['id'], @option_spr)
      assert_success response
    else
      assert_failure response
    end
  end

  def test_failed_void
    assert void = @gateway.void(123456, @option_spr)
    assert_failure void
    assert_equal 'Unauthorized', void.params['errorCode']
    assert_equal 'Unauthorized', void.params['message']
    assert_equal 'Original Payment Not Found Or You Do Not Have Access.', void.params['details'][0]
  end

  def test_success_get_payment_status
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_success, @option_spr)
    assert_success response

    # check is this transaction associated batch is "Closed".
    batch_check = @gateway.get_payment_status(response.params['batchId'], @option_spr)

    assert_success batch_check
    assert_equal 'Open', batch_check.params['status']
  end

  def test_failed_get_payment_status
    # check is this transaction associated batch is "Closed".
    batch_check = @gateway.get_payment_status(123456, @option_spr)

    assert_failure batch_check
    assert_equal 'Invalid JSON response', batch_check.params['message'][0..20]
  end

  # Must enter 6 to 10 numbers from start of card to test
  def test_successful_verify
    # Generate jwt token from key and secret. Pass generated jwt to verify function. The verify function requries a jwt for header authorization.
    jwt_response = @gateway.create_jwt(@option_spr)
    response = @gateway.verify(@card_number_verify, jwt_response.params['jwtToken'])
    assert_failure response
    assert_match 'JPMORGAN CHASE BANK, N.A.', response.params['bank']['name']
  end

  # Must enter 6 to 10 numbers from start of card to test
  def test_failed_verify
    # Generate jwt token from key and secret. Pass generated jwt to verify function. The verify function requries a jwt for header authorization.
    jwt_response = @gateway.create_jwt(@option_spr)
    @gateway.verify('123456', jwt_response.params['jwtToken'])
  rescue StandardError => e
    if e.to_s.include? 'No bank information found for bin number'
      response = { 'error' => 'No bank information found for bin number' }
      assert_match 'No bank information found for bin number', response['error']
    else
      assert_match 'No bank information found for bin number', 'error'
    end
  end

  def test_failed_verify_must_be_6_to_10_digits
    # Generate jwt token from key and secret. Pass generated jwt to verify function. The verify function requries a jwt for header authorization.
    jwt_response = @gateway.create_jwt(@option_spr)
    @gateway.verify('12345', jwt_response.params['jwtToken'])
  rescue StandardError => e
    if e.to_s.include? 'Invalid bank bin number, must be 6-10 digits'
      response = { 'error' => 'Invalid bank bin number, must be 6-10 digits' }
      assert_match 'Invalid bank bin number, must be 6-10 digits', response['error']
    else
      assert_match 'Invalid bank bin number, must be 6-10 digits', 'error'
    end
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount_purchase, @credit_card_purchase_success, @option_spr)
    end
    clean_transcript = @gateway.scrub(transcript)
    assert_scrubbed(@credit_card_purchase_success.number, clean_transcript)
    assert_scrubbed(@credit_card_purchase_success.verification_value.to_s, clean_transcript)
  end

  # Refund tests
  # Test if we can perform a refund by following steps. This is the happy path.
  #   1. Create Sale/Purchase
  #   2. Test if linked batch is Open
  #   3. Close linked batch with Sale/Purchase transaction
  #   4. Perform Refund
  def test_successful_refund_and_batch_closed
    response = @gateway.purchase(@amount_purchase, @credit_card_purchase_success, @option_spr)
    assert_success response

    # check is this transaction associated batch is "Closed".
    batch_check = @gateway.get_payment_status(response.params['batchId'], @option_spr)
    # if batch Open then fail test. Batch must be closed to perform a Refund
    if batch_check.params['status'] == 'Open'
      @gateway.close_batch(response.params['batchId'], @option_spr)

      refund = @gateway.refund(response.params['amount'].to_f * 100, response.params['cardAccount'], response.params)
      assert_success refund
      assert refund.params['status'] == 'Approved'

      assert_equal 'Approved', refund.message

    else
      assert_failure response
    end
  end
end
