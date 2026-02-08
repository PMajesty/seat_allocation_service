class Payment < ApplicationRecord
  belongs_to :order

  enum :status, {
    new: 0,
    pending: 1,
    successful: 2,
    failed: 3
  }, prefix: :payment
end
