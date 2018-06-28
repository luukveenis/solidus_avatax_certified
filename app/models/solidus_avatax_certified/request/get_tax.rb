module SolidusAvataxCertified
  module Request
    class GetTax < SolidusAvataxCertified::Request::Base
      def generate
        {
          createTransactionModel: {
            code: order.number,
            date: doc_date,
            discount: discount_total,
            commit: @commit,
            type: @doc_type ? @doc_type : 'SalesOrder',
            lines: sales_lines
          }.merge(base_tax_hash)
        }
      end

      protected

      # Sums all eligible order and line item promotion adjustments. This
      # excludes shipping promotions because we already send the discounted
      # shipment amount, so this would double count those.
      def discount_total
        order.all_adjustments.where.not(adjustable_type: "Spree::Shipment").
          promotion.eligible.sum(:amount).abs.to_f
      end

      def doc_date
        order.completed? ? order.completed_at.strftime('%F') : Date.today.strftime('%F')
      end
    end
  end
end
