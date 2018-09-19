require 'spec_helper'

RSpec.describe SolidusAvataxCertified::Request::GetTax, :vcr do
  let(:user) { create(:user, email: "test@example.com") }
  let(:california) { create(:state, state_code: "CA") }
  let(:stock_location) do
    create(
      :stock_location,
      address1: "1070 Lombard Street",
      city: "San Francisco",
      zipcode: "94109",
      state: california
    )
  end
  let(:address) do
    create(
      :address,
      address1: "42 Fake Street",
      address2: "Southeast",
      city: "Los Angeles",
      zipcode: "90210",
      state: california,
      country_iso_code: 'US',
    )
  end
  let(:order) do
    create(
      :avalara_order,
      user: user,
      line_items_count: 1,
      line_items_price: 5,
      bill_address: address,
      ship_address: address,
      stock_location: stock_location
    )
  end
  let(:shipment) { order.shipments.first }
  let(:line_item) { order.line_items.first }

  before do
    VCR.use_cassette('order_capture', allow_playback_repeats: true) do
      order
    end
  end

  describe '#generate' do
    subject { described_class.new(order, commit: false, doc_type: 'SalesOrder').generate }

    it 'creates a hash with correct values' do
      expect(subject).to include(
        createTransactionModel: {
          code: order.number,
          date: Date.today.to_s,
          discount: 0.0,
          commit: false,
          type: "SalesOrder",
          lines: [
            {
              number: "#{line_item.id}-LI",
              description: line_item.name,
              taxCode: "PC030000",
              itemCode: line_item.variant.sku,
              quantity: 1,
              amount: 5.0,
              discounted: false,
              taxIncluded: false,
              addresses: {
                shipFrom: {
                  line1: "1070 Lombard Street",
                  line2: nil,
                  city: "San Francisco",
                  region: "CA",
                  country: "US",
                  postalCode: "94109"
                }, shipTo: {
                  line1: "42 Fake Street",
                  line2: "Southeast",
                  city: "Los Angeles",
                  region: "CA",
                  country: "US",
                  postalCode: "90210"
                }
              },
              customerUsageType: nil,
              businessIdentificationNo: nil,
              exemptionCode: nil
            },
            {
              number: "#{shipment.id}-FR",
              itemCode: shipment.shipping_method.name,
              quantity: 1,
              amount: 5.0,
              description: "Shipping Charge",
              taxCode: "FR000000",
              discounted: false,
              taxIncluded: false,
              addresses: {
                shipFrom: {
                  line1: "1070 Lombard Street",
                  line2: nil,
                  city: "San Francisco",
                  region: "CA",
                  country: "US",
                  postalCode: "94109"
                }, shipTo: {
                  line1: "42 Fake Street",
                  line2: "Southeast",
                  city: "Los Angeles",
                  region: "CA",
                  country: "US",
                  postalCode: "90210"
                }
              },
              customerUsageType: nil,
              businessIdentificationNo: nil,
              exemptionCode: nil
            }
          ],
          customerCode: anything,
          companyCode: anything,
          customerUsageType: nil,
          exemptionNo: nil,
          referenceCode: order.number,
          currencyCode: "USD",
          businessIdentificationNo: nil
        }
      )
    end

    context "with a line item discount" do
      let!(:promotion) { create(:promotion, :with_line_item_adjustment, code: "test") }

      before do
        order.coupon_code = "test"
        expect(Spree::PromotionHandler::Coupon.new(order).apply).to be_successful
      end

      it "sends the full item price and an invoice discount" do
        expect(subject).to include(
          createTransactionModel: hash_including(
            discount: 5.0,
            lines: [
              hash_including(
                amount: 5.0,
                discounted: true
              ),
              anything
            ]
          )
        )
      end
    end

    context "with free shipping" do
      let!(:free_shipping) { Spree::Promotion::Actions::FreeShipping.new }
      let!(:promotion) { create(:promotion, code: "test", promotion_actions: [free_shipping]) }

      before do
        order.coupon_code = "test"
        expect(Spree::PromotionHandler::Coupon.new(order).apply).to be_successful
      end


      it "sends the discounted shipment amount" do
        expect(subject).to include(
          createTransactionModel: hash_including(
            discount: 0.0,
            lines: [
              anything,
              hash_including(
                amount: 0.0,
                discounted: false
              )
            ]
          )
        )
      end
    end

    context "with a completed order" do
      let(:completed_at) { Time.parse("2018-02-28") }
      let(:order) { create(:order, state: 'complete', completed_at: completed_at) }

      it "includes a tax date override" do
        expect(subject).to include(
          createTransactionModel: hash_including(
            taxOverride: {
              type: 'TaxDate',
              reason: 'Completed At',
              taxDate: "2018-02-28"
            }
          )
        )
      end
    end
  end
end
