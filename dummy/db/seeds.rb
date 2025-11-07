# This file should ensure the existence of records required to run the application in every environment
# (production, development, test). The code here should be idempotent so that it can be executed at any
# point in an environment's lifecycle.
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
