class User < ApplicationRecord
  has_many :expenses
  has_many :expense_shares
  has_many :expense_payers
  has_many :groups
  has_many :user_groups
  has_many :payments, class_name: "ExpensePayer", foreign_key: "receiver_id"
  has_one_attached :photo
end
