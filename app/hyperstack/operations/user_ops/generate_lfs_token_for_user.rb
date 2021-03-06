# frozen_string_literal: true

module UserOps
  class GenerateLFSTokenForUser < Hyperstack::ServerOp
    param :acting_user
    step {
      params.acting_user.generate_lfs_token
      params.acting_user.save!
    }
  end
end
