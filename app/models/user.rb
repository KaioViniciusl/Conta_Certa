class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :expenses, through: :expense_shares
  has_many :expense_shares
  has_many :expense_payers
  has_many :groups
  has_many :user_groups
  has_many :payments, class_name: "ExpensePayer", foreign_key: "receiver_id"
  has_one_attached :photo
  before_save :downcase_email

  validates :email, presence: true
  validates :password, confirmation: true, if: :password_present?

  def accept_pending_invites
    pending_invites = UserGroup.where(user_mail: email.downcase, invite_accepted: false)

    pending_invites.each do |user_group|
      user_group.update(invite_accepted: true)

      group = user_group.group
      group.add_user(self) unless group.users.include?(self)
    end
  end

  private

  def downcase_email
    self.email = email.downcase
  end

  def password_present?
    password.present?
  end
end
