class Users::RegistrationsController < Devise::RegistrationsController
  def after_sign_up_path_for(resource)
    groups_path
  end
end
