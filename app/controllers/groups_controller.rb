class GroupsController < ApplicationController
  before_action :authenticate_user!, except: [:accept_invite]
  before_action :set_group, only: [:edit, :update, :destroy, :show, :accept_invite]
  before_action :authorize_group, only: [:edit, :update, :destroy, :show]
  include GroupsHelper

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def index
    accept_pending_invites_for_current_user
    @groups = policy_scope(Group)
  end

  def show
    @expenses = @group.expenses
    @user_balance = @group.calculate_balance_by_user(current_user)
    @expense_payers = @group.expense_payers
    @users = User.where(id: @expense_payers.pluck(:user_id, :receiver_id).flatten.uniq).index_by(&:id)

    @expenses_with_status = @expenses.map do |expense|
      status = determine_user_status(expense)
      { expense: expense, status: status }
    end

    @user_balance[:users_owing] ||= {}
    @user_balance[:users_owed] ||= {}
    @user_balance[:credit] ||= 0
    @user_balance[:debit] ||= 0
    puts "User balance: #{@user_balance.inspect}"

  end

  def new
    @group = Group.new
    authorize @group
  end

  def create
    @group = current_user.groups.new(group_params)
    authorize @group

    if @group.save
      @group.generate_token
      @group.user_groups.find_or_create_by(user: current_user, user_mail: current_user.email, invite_accepted: true)
      handle_invitations(params[:invite_emails].to_s.split(",").map(&:strip))
      redirect_to group_path(@group), notice: "Grupo criado com sucesso e convites enviados."
    else
      @errors = @group.errors.full_messages.map do |msg|
        msg = msg.sub(/.*?O/, 'O')
        msg = msg.gsub(/\band\b/, '').strip
      end
      formatted_errors = @errors.to_sentence(words_connector: ', ', two_words_connector: ' ')
      flash[:alertgroup] = formatted_errors
      redirect_to new_group_path
    end
  end

  def edit
    # @group já é definido por set_group e authorize @group é chamado por before_action
  end

  def update
    authorize @group

    if @group.update(group_params)
      @group.generate_token
      @group.user_groups.find_or_create_by(user: current_user, user_mail: current_user.email, invite_accepted: true)
      handle_invitations(params[:invite_emails].to_s.split(",").map(&:strip))
      redirect_to group_path(@group), notice: "Grupo atualizado com sucesso e convites enviados."
    else
      @errors = @group.errors.full_messages.map do |msg|
        msg = msg.sub(/.*?O/, 'O')
        msg = msg.gsub(/\band\b/, '').strip
      end
      formatted_errors = @errors.present? ? @errors.to_sentence(words_connector: ', ', two_words_connector: ' e ') : "Ocorreu um erro ao atualizar o grupo."

      flash[:alertgroup] = formatted_errors
      redirect_to edit_group_path and return
    end
  end

  def accept_pending_invites_for_current_user
    if user_signed_in?
      current_user.accept_pending_invites
    end
  end

  def accept_invite
    skip_authorization
    unless @group.last_token == params[:token]
      flash[:token] = "Token de convite expirado ou inválido."
      if current_user
        redirect_to groups_path and return
      else
        redirect_to new_user_session_path and return
      end
    end

    if user_signed_in?
      user_group = @group.user_groups.find_by(user: current_user, user_mail: current_user.email,
                                              invite_accepted: true)
      flash[:notice] = user_group ? "Você já faz parte deste grupo." : "Você foi adicionado ao grupo!"
      @group.add_user(current_user) unless user_group
      @group.generate_token
      redirect_to @group
    else
      session[:invite_token] = params[:token]
      redirect_to new_user_session_path, notice: "Faça login ou cadastre-se para aceitar o convite."
    end
  end

  def generate_invite_link
    @group.update(last_token: SecureRandom.urlsafe_base64)
    redirect_to group_path(@group), notice: "Link de convite gerado com sucesso."
  end

  def destroy
    authorize @group

     if @group.expenses.any?
      flash[:alertgroup] = "Não é possível excluir o grupo porque ele já tem despesas associadas."
      redirect_to @group
     else
      @group.user_groups.destroy_all
      @group.destroy
      redirect_to groups_path, notice: "Grupo #{@group.name_group} foi deletado com sucesso."
     end
  end

  def user_not_authorized
    flash[:alertgroup] = "Desculpe, mas apenas o usuário que criou o grupo pode deletá-lo."
    redirect_to @group
  end

  private

  def group_params
    params.require(:group).permit(:name_group, :observation, :description_group, :photo)
  end

  def set_group
    @group = Group.find_by(id: params[:id])
    return if @group

    redirect_to root_path, notice: "Grupo não encontrado."
  end

  def handle_invitations(invite_emails)
    invite_emails.each do |email|
      user = User.find_by(email: email.downcase)
      if user
        create_user_group_for_existing_user(user)
      else
        create_user_group_for_new_email(email)
      end
    end
  end

  def create_user_group_for_existing_user(user)
    user_group = UserGroup.find_or_initialize_by(user: user, group: @group, user_mail: user.email.downcase)

    if user_group.new_record?
      user_group.invite_accepted = (user == current_user)
      user_group.save
    end

    if user != current_user
      UserMailer.invite_email(@group.id, user.email.downcase, user).deliver_now
    end
  end

  def create_user_group_for_new_email(email)
    UserGroup.create(group: @group, user_mail: email.downcase)
    UserMailer.invite_email(@group.id, email.downcase).deliver_now
  end

  def authorize_group
    authorize @group
  end

  def calculate_group_balances(user)
    balances = Hash.new { |hash, key| hash[key] = { credit: 0, debit: 0 } }

    @group.expenses.each do |expense|
      total_amount = expense.amount
      total_shares = expense.expense_shares.count
      per_user_amount = total_amount / total_shares.to_f

      expense.expense_shares.each do |share|
        user_balance = balances[share.user]

        user_balance[:debit] += (per_user_amount - share.share_amount) || 0
        user_balance[:credit] += (share.share_amount - per_user_amount) || 0
      end
    end

    balances
  end

  def determine_user_status(expense)
    share = expense.expense_shares.find_by(user: current_user)

    return 'not_involved' unless share

    user_share_amount = share.share_amount
    total_amount = expense.amount
    total_shares = expense.expense_shares.sum(:share_amount)
    per_user_amount = total_amount / total_shares

    balance = user_share_amount - per_user_amount

    if balance < 0
      'debt'
    elsif balance > 0
      'credit'
    else
      'not_involved'
    end
  end
end
