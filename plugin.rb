# frozen_string_literal: true
# name: discourse-animated-avatars
# about: This plugin adds support for animated avatars
# version: 0.1
# url: https://github.com/discourse/discourse-animated-avatars

require_relative "lib/discourse_animated_avatars/engine"

after_initialize do
  reloadable_patch do
    gifsicle_installed =
      begin
        Discourse::Utils.execute_command(
          "gifsicle",
          "--version",
          "&>",
          "/dev/null",
          failure_message: "gifsicle not found",
        )
        true
      rescue StandardError
        false
      end

    # new crop functions if gifsicle is installed
    if gifsicle_installed
      UploadCreator.prepend(DiscourseAnimatedAvatars::UploadCreatorGifsicleExtension)
    else
      # fallback if no gifsicle, no cropping for animated avatars
      UploadCreator.prepend(DiscourseAnimatedAvatars::UploadCreatorNoGifsicleExtension)
    end
    UploadCreator.prepend(DiscourseAnimatedAvatars::UploadCreatorAnimatedWebpExtension)
    UploadCreator.prepend(DiscourseAnimatedAvatars::UploadCreatorGifToWebpExtension)

    OptimizedImage.prepend(DiscourseAnimatedAvatars::OptimizedImageExtension)
    UserAvatarsController.prepend(DiscourseAnimatedAvatars::UserAvatarsControllerExtension)
  end

  add_to_class(:user, :animated_avatar) do
    gating_methods = SiteSetting.animated_avatars_gating_methods.split("|")
    pass_tl_check =
      gating_methods.include?("trust_level") &&
        trust_level >= SiteSetting.animated_avatars_min_trust_level_to_display
    allowed_group_ids = SiteSetting.animated_avatars_allowed_groups.split("|").map(&:to_i)
    pass_group_check =
      gating_methods.include?("group") && allowed_group_ids.present? &&
        groups.where(id: allowed_group_ids).exists?
    pass_gating_check = staff? || pass_tl_check || pass_group_check
    uploaded_avatar&.url if uploaded_avatar&.animated? && pass_gating_check
  end

  add_to_serializer(:basic_user, :animated_avatar) do
    user.try(:animated_avatar)
  rescue StandardError
    nil
  end
  add_to_serializer(:post, :animated_avatar) do
    object.user.try(:animated_avatar)
  rescue StandardError
    nil
  end
end

Discourse::Application.routes.append do
  %i[gif webp].each do |fmt|
    get "user_avatar/:hostname/:username/:size/:version.#{fmt}" => "user_avatars#show",
        :constraints => {
          hostname: /[\w\.-]+/,
          size: /\d+/,
          username: RouteFormat.username,
          format: fmt,
        }
  end
end
