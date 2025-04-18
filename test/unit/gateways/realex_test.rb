require 'test_helper'

class RealexTest < Test::Unit::TestCase
  include CommStub

  class ActiveMerchant::Billing::RealexGateway
    # For the purposes of testing, lets redefine some protected methods as public.
    public :build_purchase_or_authorization_request
    public :build_refund_request
    public :build_void_request
    public :build_capture_request
    public :build_verify_request
    public :build_credit_request
  end

  def setup
    @login = 'your_merchant_id'
    @password = 'your_secret'
    @account = 'your_account'
    @rebate_secret = 'your_rebate_secret'
    @refund_secret = 'your_refund_secret'

    @gateway = RealexGateway.new(
      login: @login,
      password: @password,
      account: @account
    )

    @gateway_with_account = RealexGateway.new(
      login: @login,
      password: @password,
      account: 'bill_web_cengal'
    )

    @credit_card = CreditCard.new(
      number: '4263971921001307',
      month: 8,
      year: 2008,
      first_name: 'Longbob',
      last_name: 'Longsen',
      brand: 'visa'
    )

    @options = {
      order_id: '1'
    }

    @address = {
      name: 'Longbob Longsen',
      address1: '123 Fake Street',
      city: 'Belfast',
      state: 'Antrim',
      country: 'Northern Ireland',
      zip: 'BT2 8XX'
    }

    @amount = 100
  end

  def test_initialize_sets_refund_and_credit_hashes
    refund_secret = 'refund'
    rebate_secret = 'rebate'

    gateway = RealexGateway.new(
      login: @login,
      password: @password,
      rebate_secret:,
      refund_secret:
    )

    assert gateway.options[:refund_hash] == Digest::SHA1.hexdigest(rebate_secret)
    assert gateway.options[:credit_hash] == Digest::SHA1.hexdigest(refund_secret)
  end

  def test_initialize_with_nil_refund_and_rebate_secrets
    gateway = RealexGateway.new(
      login: @login,
      password: @password,
      rebate_secret: nil,
      refund_secret: nil
    )

    assert_false gateway.options.key?(:refund_hash)
    assert_false gateway.options.key?(:credit_hash)
  end

  def test_initialize_without_refund_and_rebate_secrets
    gateway = RealexGateway.new(
      login: @login,
      password: @password
    )

    assert_false gateway.options.key?(:refund_hash)
    assert_false gateway.options.key?(:credit_hash)
  end

  def test_hash
    gateway = RealexGateway.new(
      login: 'thestore',
      password: 'mysecret'
    )
    Time.stubs(:now).returns(Time.new(2001, 4, 3, 12, 32, 45))
    gateway.expects(:ssl_post).with(anything, regexp_matches(/9af7064afd307c9f988e8dfc271f9257f1fc02f6/)).returns(successful_purchase_response)
    gateway.purchase(29900, credit_card('5105105105105100'), order_id: 'ORD453-11')
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    assert response.test?
  end

  def test_unsuccessful_purchase
    @gateway.expects(:ssl_post).returns(unsuccessful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_failure response
    assert response.test?
  end

  def test_purchase_passes_stored_credential
    options = @options.merge({
      stored_credential: {
        initial_transaction: true,
        reason_type: 'unscheduled',
        initiator: 'cardholder',
        network_transaction_id: nil
      }
    })

    stub_comms do
      @gateway.purchase(@amount, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      stored_credential_params = Nokogiri::XML.parse(data).xpath('//storedcredential')

      assert_equal stored_credential_params.xpath('type').text, 'oneoff'
      assert_equal stored_credential_params.xpath('initiator').text, 'cardholder'
      assert_equal stored_credential_params.xpath('sequence').text, 'first'
      assert_equal stored_credential_params.xpath('srd').text, ''
    end.respond_with(successful_purchase_response)
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    assert_success @gateway.refund(@amount, '1234;1234;1234')
  end

  def test_unsuccessful_refund
    @gateway.expects(:ssl_post).returns(unsuccessful_refund_response)
    assert_failure @gateway.refund(@amount, '1234;1234;1234')
  end

  def test_successful_credit
    @gateway.expects(:ssl_post).returns(successful_credit_response)
    assert_success @gateway.credit(@amount, @credit_card, @options)
  end

  def test_unsuccessful_credit
    @gateway.expects(:ssl_post).returns(unsuccessful_credit_response)
    assert_failure @gateway.credit(@amount, @credit_card, @options)
  end

  def test_supported_countries
    assert_equal %w[IE GB FR BE NL LU IT US CA ES], RealexGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express diners_club], RealexGateway.supported_cardtypes
  end

  def test_avs_result_not_supported
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_nil response.avs_result['code']
  end

  def test_cvv_result
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'M', response.cvv_result['code']
  end

  def test_malformed_xml
    @gateway.expects(:ssl_post).returns(malformed_unsuccessful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_failure response
    assert_equal '[ test system ] This is  not awesome', response.params['message']
    assert response.test?
  end

  def test_capture_xml
    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_capture_xml = <<~SRC
      <request timestamp="20090824160201" type="settle">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <amount>100</amount>
        <orderid>1</orderid>
        <pasref>4321</pasref>
        <authcode>1234</authcode>
        <sha1hash>ef0a6c485452f3f94aff336fa90c6c62993056ca</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_capture_xml, @gateway.build_capture_request(@amount, '1;4321;1234', {})
  end

  def test_purchase_xml
    options = {
      order_id: '1',
      ip: '123.456.789.0'
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_purchase_request_xml = <<~SRC
      <request timestamp="20090824160201" type="auth">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency="EUR">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="1"/>
        <sha1hash>3499d7bc8dbacdcfba2286bd74916d026bae630f</sha1hash>
        <tssinfo>
          <custipaddress>123.456.789.0</custipaddress>
        </tssinfo>
      </request>
    SRC

    assert_xml_equal valid_purchase_request_xml, @gateway.build_purchase_or_authorization_request(:purchase, @amount, @credit_card, options)
  end

  def test_purchase_xml_with_ipv6
    options = {
      order_id: '1',
      ip: '2a02:c7d:da18:ac00:6d10:4f13:1795:4890'
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_purchase_request_xml = <<~SRC
      <request timestamp="20090824160201" type="auth">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency="EUR">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="1"/>
        <sha1hash>3499d7bc8dbacdcfba2286bd74916d026bae630f</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_purchase_request_xml, @gateway.build_purchase_or_authorization_request(:purchase, @amount, @credit_card, options)
  end

  def test_void_xml
    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_void_request_xml = <<~SRC
      <request timestamp="20090824160201" type="void">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <pasref>4321</pasref>
        <authcode>1234</authcode>
        <sha1hash>4132600f1dc70333b943fc292bd0ca7d8e722f6e</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_void_request_xml, @gateway.build_void_request('1;4321;1234', {})
  end

  def test_verify_xml
    options = {
      order_id: '1'
    }
    @gateway.expects(:new_timestamp).returns('20181026114304')

    valid_verify_request_xml = <<~SRC
      <request timestamp="20181026114304" type="otb">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <sha1hash>d53aebf1eaee4c3ff4c30f83f27b80ce99ba5644</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_verify_request_xml, @gateway.build_verify_request(@credit_card, options)
  end

  def test_auth_xml
    options = {
      order_id: '1'
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_auth_request_xml = <<~SRC
      <request timestamp="20090824160201" type="auth">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency=\"EUR\">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="0"/>
        <sha1hash>3499d7bc8dbacdcfba2286bd74916d026bae630f</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_auth_request_xml, @gateway.build_purchase_or_authorization_request(:authorization, @amount, @credit_card, options)
  end

  def test_refund_xml
    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_refund_request_xml = <<~SRC
      <request timestamp="20090824160201" type="rebate">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <pasref>4321</pasref>
        <authcode>1234</authcode>
        <amount currency="EUR">100</amount>
        <autosettle flag="1"/>
        <sha1hash>ef0a6c485452f3f94aff336fa90c6c62993056ca</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_refund_request_xml, @gateway.build_refund_request(@amount, '1;4321;1234', {})
  end

  def test_refund_with_rebate_secret_xml
    gateway = RealexGateway.new(login: @login, password: @password, account: @account, rebate_secret: @rebate_secret)

    gateway.expects(:new_timestamp).returns('20090824160201')

    valid_refund_request_xml = <<~SRC
      <request timestamp="20090824160201" type="rebate">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <pasref>4321</pasref>
        <authcode>1234</authcode>
        <amount currency="EUR">100</amount>
        <refundhash>f94ff2a7c125a8ad87e5683114ba1e384889240e</refundhash>
        <autosettle flag="1"/>
        <sha1hash>ef0a6c485452f3f94aff336fa90c6c62993056ca</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_refund_request_xml, gateway.build_refund_request(@amount, '1;4321;1234', {})
  end

  def test_credit_xml
    options = {
      order_id: '1'
    }

    @gateway.expects(:new_timestamp).returns('20190717161006')

    valid_credit_request_xml = <<~SRC
        <request timestamp="20190717161006" type="credit">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency="EUR">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="1"/>
        <sha1hash>73ff566dcfc3a73bebf1a2d387316162111f030e</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_credit_request_xml, @gateway.build_credit_request(@amount, @credit_card, options)
  end

  def test_credit_with_refund_secret_xml
    gateway = RealexGateway.new(login: @login, password: @password, account: @account, refund_secret: @refund_secret)

    gateway.expects(:new_timestamp).returns('20190717161006')

    valid_credit_request_xml = <<~SRC
      <request timestamp="20190717161006" type="credit">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency="EUR">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <refundhash>bbc192c6eac0132a039c23eae8550a22907c6796</refundhash>
        <autosettle flag="1"/>
        <sha1hash>73ff566dcfc3a73bebf1a2d387316162111f030e</sha1hash>
      </request>
    SRC

    assert_xml_equal valid_credit_request_xml, gateway.build_credit_request(@amount, @credit_card, @options)
  end

  def test_auth_with_address
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    options = {
      order_id: '1',
      billing_address: @address,
      shipping_address: @address
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    response = @gateway.authorize(@amount, @credit_card, options)
    assert_instance_of Response, response
    assert_success response
    assert response.test?
  end

  def test_zip_in_shipping_address
    @gateway.expects(:ssl_post).with(anything, regexp_matches(/<code>28\|123<\/code>/)).returns(successful_purchase_response)

    options = {
      order_id: '1',
      shipping_address: @address
    }

    @gateway.authorize(@amount, @credit_card, options)
  end

  def test_zip_in_billing_address
    @gateway.expects(:ssl_post).with(anything, regexp_matches(/<code>28\|123<\/code>/)).returns(successful_purchase_response)

    options = {
      order_id: '1',
      billing_address: @address
    }

    @gateway.authorize(@amount, @credit_card, options)
  end

  def test_transcript_scrubbing
    assert_equal scrubbed_transcript, @gateway.scrub(transcript)
  end

  def test_three_d_secure_1
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    options = {
      order_id: '1',
      three_d_secure: {
        cavv: '1234',
        eci: '1234',
        xid: '1234',
        version: '1.0.2'
      }
    }

    response = @gateway.authorize(@amount, @credit_card, options)
    assert_equal 'M', response.cvv_result['code']
  end

  def test_auth_xml_with_three_d_secure_1
    options = {
      order_id: '1',
      three_d_secure: {
        cavv: '1234',
        eci: '1234',
        xid: '1234',
        version: '1.0.2'
      }
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_auth_request_xml = <<~SRC
      <request timestamp="20090824160201" type="auth">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency=\"EUR\">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="0"/>
        <sha1hash>3499d7bc8dbacdcfba2286bd74916d026bae630f</sha1hash>
        <mpi>
          <cavv>1234</cavv>
          <xid>1234</xid>
          <eci>1234</eci>
          <message_version>1</message_version>
        </mpi>
      </request>
    SRC

    assert_xml_equal valid_auth_request_xml, @gateway.build_purchase_or_authorization_request(:authorization, @amount, @credit_card, options)
  end

  def test_auth_xml_with_three_d_secure_2
    options = {
      order_id: '1',
      three_d_secure: {
        cavv: '1234',
        eci: '1234',
        ds_transaction_id: '1234',
        version: '2.1.0'
      }
    }

    @gateway.expects(:new_timestamp).returns('20090824160201')

    valid_auth_request_xml = <<~SRC
      <request timestamp="20090824160201" type="auth">
        <merchantid>your_merchant_id</merchantid>
        <account>your_account</account>
        <orderid>1</orderid>
        <amount currency=\"EUR\">100</amount>
        <card>
          <number>4263971921001307</number>
          <expdate>0808</expdate>
          <chname>Longbob Longsen</chname>
          <type>VISA</type>
          <issueno></issueno>
          <cvn>
            <number></number>
            <presind></presind>
          </cvn>
        </card>
        <autosettle flag="0"/>
        <sha1hash>3499d7bc8dbacdcfba2286bd74916d026bae630f</sha1hash>
        <mpi>
          <authentication_value>1234</authentication_value>
          <ds_trans_id>1234</ds_trans_id>
          <eci>1234</eci>
          <message_version>2.1.0</message_version>
        </mpi>
      </request>
    SRC

    assert_xml_equal valid_auth_request_xml, @gateway.build_purchase_or_authorization_request(:authorization, @amount, @credit_card, options)
  end

  private

  def successful_purchase_response
    <<~RESPONSE
      <response timestamp='20010427043422'>
        <merchantid>your merchant id</merchantid>
        <account>account to use</account>
        <orderid>order id from request</orderid>
        <authcode>authcode received</authcode>
        <result>00</result>
        <message>[ test system ] message returned from system</message>
        <pasref> realex payments reference</pasref>
        <cvnresult>M</cvnresult>
        <batchid>batch id for this transaction (if any)</batchid>
        <cardissuer>
          <bank>Issuing Bank Name</bank>
          <country>Issuing Bank Country</country>
          <countrycode>Issuing Bank Country Code</countrycode>
          <region>Issuing Bank Region</region>
        </cardissuer>
        <tss>
          <result>89</result>
          <check id="1000">9</check>
          <check id="1001">9</check>
        </tss>
        <sha1hash>7384ae67....ac7d7d</sha1hash>
        <md5hash>34e7....a77d</md5hash>
      </response>"
    RESPONSE
  end

  def unsuccessful_purchase_response
    <<~RESPONSE
      <response timestamp='20010427043422'>
        <merchantid>your merchant id</merchantid>
        <account>account to use</account>
        <orderid>order id from request</orderid>
        <authcode>authcode received</authcode>
        <result>01</result>
        <message>[ test system ] message returned from system</message>
        <pasref> realex payments reference</pasref>
        <cvnresult>M</cvnresult>
        <batchid>batch id for this transaction (if any)</batchid>
        <cardissuer>
          <bank>Issuing Bank Name</bank>
          <country>Issuing Bank Country</country>
          <countrycode>Issuing Bank Country Code</countrycode>
          <region>Issuing Bank Region</region>
        </cardissuer>
        <tss>
          <result>89</result>
          <check id="1000">9</check>
          <check id="1001">9</check>
        </tss>
        <sha1hash>7384ae67....ac7d7d</sha1hash>
        <md5hash>34e7....a77d</md5hash>
      </response>"
    RESPONSE
  end

  def malformed_unsuccessful_purchase_response
    <<~RESPONSE
      <response timestamp='20010427043422'>
        <merchantid>your merchant id</merchantid>
        <account>account to use</account>
        <orderid>order id from request</orderid>
        <authcode>authcode received</authcode>
        <result>01</result>
        <message>[ test system ] This is & not awesome</message>
        <pasref> realex payments reference</pasref>
        <cvnresult>M</cvnresult>
        <batchid>batch id for this transaction (if any)</batchid>
        <cardissuer>
          <bank>Issuing Bank Name</bank>
          <country>Issuing Bank Country</country>
          <countrycode>Issuing Bank Country Code</countrycode>
          <region>Issuing Bank Region</region>
        </cardissuer>
        <tss>
          <result>89</result>
          <check id="1000">9</check>
          <check id="1001">9</check>
        </tss>
        <sha1hash>7384ae67....ac7d7d</sha1hash>
        <md5hash>34e7....a77d</md5hash>
      </response>"
    RESPONSE
  end

  def successful_refund_response
    <<~RESPONSE
      <response timestamp='20010427043422'>
        <merchantid>your merchant id</merchantid>
        <account>account to use</account>
        <orderid>order id from request</orderid>
        <authcode>authcode received</authcode>
        <result>00</result>
        <message>[ test system ] message returned from system</message>
        <pasref> realex payments reference</pasref>
        <cvnresult>M</cvnresult>
        <batchid>batch id for this transaction (if any)</batchid>
        <sha1hash>7384ae67....ac7d7d</sha1hash>
        <md5hash>34e7....a77d</md5hash>
      </response>"
    RESPONSE
  end

  def unsuccessful_refund_response
    <<~RESPONSE
      <response timestamp='20010427043422'>
        <merchantid>your merchant id</merchantid>
        <account>account to use</account>
        <orderid>order id from request</orderid>
        <authcode>authcode received</authcode>
        <result>508</result>
        <message>[ test system ] You may only rebate up to 115% of the original amount.</message>
        <pasref> realex payments reference</pasref>
        <cvnresult>M</cvnresult>
        <batchid>batch id for this transaction (if any)</batchid>
        <sha1hash>7384ae67....ac7d7d</sha1hash>
        <md5hash>34e7....a77d</md5hash>
      </response>"
    RESPONSE
  end

  def successful_credit_response
    <<-RESPONSE
    <response timestamp="20190717205030">
    <merchantid>spreedly</merchantid>
    <account>internet</account>
    <orderid>57a861e97273371e6f1b1737a9bc5710</orderid>
    <authcode>005030</authcode>
    <result>00</result>
    <cvnresult>U</cvnresult>
    <avspostcoderesponse>U</avspostcoderesponse>
    <avsaddressresponse>U</avsaddressresponse>
    <batchid>674655</batchid>
    <message>AUTH CODE: 005030</message>
    <pasref>15633930303644971</pasref>
    <timetaken>0</timetaken>
    <authtimetaken>0</authtimetaken>
    <cardissuer>
      <bank>AIB BANK</bank>
      <country>IRELAND</country>
      <countrycode>IE</countrycode>
      <region>EUR</region>
    </cardissuer>
    <sha1hash>6d2fc...67814</sha1hash>
  </response>"
    RESPONSE
  end

  def unsuccessful_credit_response
    <<-RESPONSE
    <response timestamp="20190717210119">
    <result>502</result>
    <message>Refund Hash not present.</message>
    <orderid>_refund_fd4ea2d10b339011bdba89f580c5b207</orderid>
  </response>"
    RESPONSE
  end

  def transcript
    <<-REQUEST
    <request timestamp="20150722170750" type="auth">
      <merchantid>your merchant id</merchantid>
      <orderid>445472dc5ea848fec1c1720a07d5710b</orderid>
      <amount currency="EUR">10000</amount>
      <card>
        <number>4000126842489127</number>
        <expdate>0620</expdate>
        <chname>Longbob Longsen</chname>
        <type>VISA</type>
        <issueno/>
        <cvn>
          <number>123</number>
          <presind>1</presind>
        </cvn>
      </card>
      <autosettle flag="1"/>
      <sha1hash>d22109765de91b75e7ad2e5d2fcf8a88235019d9</sha1hash>
      <comments>
        <comment id="1">Test Realex Purchase</comment>
      </comments>
      <tssinfo>
        <address type="billing">
          <code>90210</code>
          <country>US</country>
        </address>
      </tssinfo>
    </request>
    REQUEST
  end

  def scrubbed_transcript
    <<-REQUEST
    <request timestamp="20150722170750" type="auth">
      <merchantid>your merchant id</merchantid>
      <orderid>445472dc5ea848fec1c1720a07d5710b</orderid>
      <amount currency="EUR">10000</amount>
      <card>
        <number>[FILTERED]</number>
        <expdate>0620</expdate>
        <chname>Longbob Longsen</chname>
        <type>VISA</type>
        <issueno/>
        <cvn>
          <number>[FILTERED]</number>
          <presind>1</presind>
        </cvn>
      </card>
      <autosettle flag="1"/>
      <sha1hash>d22109765de91b75e7ad2e5d2fcf8a88235019d9</sha1hash>
      <comments>
        <comment id="1">Test Realex Purchase</comment>
      </comments>
      <tssinfo>
        <address type="billing">
          <code>90210</code>
          <country>US</country>
        </address>
      </tssinfo>
    </request>
    REQUEST
  end

  def assert_xml_equal(expected, actual)
    assert_xml_equal_recursive(Nokogiri::XML(expected).root, Nokogiri::XML(actual).root)
  end

  def assert_xml_equal_recursive(a, b)
    assert_equal(a.name, b.name)
    assert_equal(a.text, b.text)
    a.attributes.zip(b.attributes).each do |(_, a1), (_, b1)|
      assert_equal a1.name, b1.name
      assert_equal a1.value, b1.value
    end
    a.children.zip(b.children).all? { |a1, b1| assert_xml_equal_recursive(a1, b1) }
  end
end
