class ExpensesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group
  before_action :set_expense, only: [:show, :update, :destroy]

  def index
    @expenses = @group.expenses.order(:date)
    @user_balances = calculate_user_balances
  end

  def new
    @expense = Expense.new
    @users = @group.users
  end

  def create
    @expense = @group.expenses.new(expense_params)
    @expense.user = current_user

    if @expense.save
      process_expense_shares(params[:expense_shares])
      redirect_to group_path(@group), notice: "Sua despesa foi criada."
    else
      render :new
    end
  end

  def update
    if @expense.update(expense_params)
      handle_expense_shares(params[:expense_shares])
      redirect_to group_expense_path(@group, @expense), notice: "Sua despesa foi atualizada."
    else
      render :edit
    end
  end

  def show
    @debts = @group.calculate_owed_amounts_with_payments
  end

  def destroy
    @expense.destroy
    @group.user_groups.each(&:update_credit_and_debit)
    redirect_to group_path(@group), notice: "Sua despesa foi removida."
  end

  private

  def set_group
    @group = Group.find(params[:group_id])
  end

  def set_expense
    @expense = @group.expenses.find(params[:id])
  end

  def expense_params
    params.require(:expense).permit(:name_expense, :description, :date, :amount)
  end

  def handle_expense_shares(expense_shares_params)
    return unless expense_shares_params.is_a?(Hash)

    ExpenseShare.where(expense: @expense).destroy_all

    expense_shares_params.each do |user_id, share_amount|
      ExpenseShare.create(expense: @expense, user_id: user_id.to_i, share_amount: share_amount.to_f)
    end
  end

  def process_expense_shares(expense_shares_params)
    expense_shares_params.each do |user_id, share_data|
      next unless share_data["selected"] == "1"

      ExpenseShare.create(
        expense: @expense,
        user_id: user_id.to_i,
        share_amount: share_data["amount"].to_f,
      )
    end
  end
end
